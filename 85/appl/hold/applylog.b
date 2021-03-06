implement Applylog;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "string.m";
	str: String;

include "keyring.m";
	kr: Keyring;

include "daytime.m";
	daytime: Daytime;

include "/appl/cmd/install/logs.m";
	logs: Logs;
	Db, Entry, Byname, Byseq: import logs;
	S: import logs;

include "arg.m";
include "filter.m";
	inflate: Filter;
INFLATEPATH: con "/dis/lib/inflate.dis";

Applylog: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Apply, Applydb, Install, Asis, Skip: con iota;

client:	ref Db;	# client current state from client log
updates:	ref Db;	# state delta from new section of server log

nerror := 0;
nconflict := 0;
debug := 0;
verbose := 0;
resolve := 0;
setuid := 0;
setgid := 0;
nflag := 0;
clientroot: string;
srvroot: string;
logfd: ref Sys->FD;
now := 0;
gen := 0;
noerr := 0;
xflag := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;

	bufio = load Bufio Bufio->PATH;
	ensure(bufio, Bufio->PATH);
	str = load String String->PATH;
	ensure(str, String->PATH);
	kr = load Keyring Keyring->PATH;
	ensure(kr, Keyring->PATH);
	daytime = load Daytime Daytime->PATH;
	ensure(daytime, Daytime->PATH);
	logs = load Logs Logs->PATH;
	ensure(logs, Logs->PATH);
	logs->init(bufio);
	inflate = load Filter INFLATEPATH;
	inflate->init();

	arg := load Arg Arg->PATH;
	ensure(arg, Arg->PATH);
	arg->init(args);
	arg->setusage("applylog [-vuged] [-sc] clientlog clientroot serverroot [path ... ] <serverlog");
	dump := 0;
	while((o := arg->opt()) != 0)
		case o {
		'd' =>	dump = 1; debug = 1;
		'e' =>	noerr = 1;
		'g' =>	setgid = 1;
		'n' =>	nflag = 1; verbose = 1;
		's' or 'c' =>	resolve = o;
		'u' =>	setuid = 1;
		'v' =>	verbose = 1;
		'x' =>	xflag = 1;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args < 3)
		arg->usage();
	arg = nil;

	now = daytime->now();
	client = Db.new("client log");
	updates = Db.new("update log");
	clientlog := hd args; args = tl args;
	clientroot = hd args; args = tl args;
	srvroot = hd args; args = tl args;
	if(args != nil)
		error("restriction by path not yet done");

	checkroot(clientroot, "client root");
	checkroot(srvroot, "server root");

	# replay the client log to build last installation state of files taken from server
	logfd = sys->open(clientlog, Sys->OREAD);
	if(logfd == nil)
		error(sys->sprint("can't open %s: %r", clientlog));
	f := bufio->fopen(logfd, Sys->OREAD);
	if(f == nil)
		error(sys->sprint("can't open %s: %r", clientlog));
	while((log := readlog(f)) != nil)
		replaylog(client, log);
	f = nil;
	sys->seek(logfd, big 0, 2);
	if(dump)
		dumpstate();
	if(debug){
		sys->print("	CLIENT STATE\n");
		client.sort(Byname);
		dumpdb(client, 0);
	}

	# read server's log and use the new section to build a sequence of update actions
	minseq := big 0;
	f = bufio->fopen(sys->fildes(0), Sys->OREAD);
	while((log = readlog(f)) != nil)
		if(log.seq > minseq)
			updatelog(updates, log);
	updates.sort(Byseq);
	if(debug){
		sys->print("	SEQUENCED UPDATES\n");
		dumpdb(updates, 1);
	}

	# apply those actions
	skip := 0;
	for(i := 0; i < updates.nstate; i++){
		e := updates.state[i];
		ce := client.look(e.path);
		case chooseaction(e, ce) {
		Install =>
			if(xflag){
				if(e.contents != nil && ce != nil && ce.contents != nil)
					sys->print("%s %s %s\n", e.path, hd e.contents, hd ce.contents);
				else if(e.contents != nil)
					sys->sprint("%s %s 0\n", e.path, hd e.contents);
				else if(ce != nil && ce.contents != nil)
					sys->print("%s 0 %s\n", e.path, hd ce.contents);
				else 
					sys->print("%s 0 0\n", e.path);
				continue;
			}
			if(nflag || debug)
				sys->print("resolve %q to install\n", e.path);
			c := e;
			c.action = 'a';	# force (re)creation/installation
			if(!enact(c)){
				skip = 1;
				continue;	# don't update db
			}
		Apply =>
			if(!enact(e)){
				skip = 1;
				continue;	# don't update db
			}
		Applydb =>
			if(nflag || debug)
				sys->print("resolve %q to update db\n", e.path);
			# carry on to update the log
		Asis =>
			if(debug)
				sys->print("resolve %q to client\n", e.path);
			#continue;
		Skip =>
			if(debug)
				sys->print("conflict %q\n", e.path);
			skip = 1;
			continue;
		* =>
			error("internal error: unexpected result from chooseaction");
		}
	}
	if(nconflict)
		raise sys->sprint("fail:%d conflicts", nconflict);
	if(nerror)
		raise sys->sprint("fail:%d errors", nerror);
}

checkroot(dir: string, what: string)
{
	(ok, d) := sys->stat(dir);
	if(ok < 0)
		error(sys->sprint("can't stat %s %q: %r", what, dir));
	if((d.mode & Sys->DMDIR) == 0)
		error(sys->sprint("%s %q: not a directory", what, dir));
}

readlog(in: ref Iobuf): ref Entry
{
	(e, err) := Entry.read(in);
	if(err != nil)
		error(err);
	return e;
}

#
# replay a log to reach the state wrt files previously taken from the server
#
replaylog(db: ref Db, log: ref Entry)
{
	e := db.look(log.path);
	indb := e != nil && !e.removed();
	case log.action {
	'a' =>	# add new file
		if(indb){
			note(sys->sprint("%q duplicate create", log.path));
			return;
		}
	'c' =>	# contents
		if(!indb){
			note(sys->sprint("%q contents but no entry", log.path));
			return;
		}
	'd' =>	# delete
		if(!indb){
			note(sys->sprint("%q deleted but no entry", log.path));
			return;
		}
		if(e.d.mtime > log.d.mtime){
			note(sys->sprint("%q deleted but it's newer", log.path));
			return;
		}
	'm' =>	# metadata
		if(!indb){
			note(sys->sprint("%q metadata but no entry", log.path));
			return;
		}
	* =>
		error(sys->sprint("bad log entry: %bd %bd", log.seq>>32, log.seq & big 16rFFFFFFFF));
	}
	update(db, e, log);
}

#
# run through the new section of the server log,
# building up a state that eliminates redundant actions
#
updatelog(db: ref Db, log: ref Entry)
{
	update(db, db.look(log.path), log);
}

#
# update file state e to reflect the effect of the log,
# creating a new entry if necessary
#
update(db: ref Db, e: ref Entry, log: ref Entry)
{
	if(e == nil)
		e = db.entry(log.seq, log.path, log.d);
	e.update(log);
}

chooseaction(e: ref Entry, db: ref Entry): int
{
	indb := db != nil && !db.removed();	# previously arrived from server

	unchanged := indb  && samestat(e.d, db.d) 
		&& ((e.d.mode & Sys->DMDIR) ||  hd e.contents == hd db.contents);
	if(unchanged && (e.action != 'm' || samemeta(e.d, db.d)))
		return Skip;
	if(e.action == 'd'){
		if(indb)
			return Applydb;
		return Asis;
	}
	case resolve {
	'c' =>
		return Asis;
	's' =>
		if(!unchanged)
			return Install;
		return Apply;
	* =>
		# describe source of conflict
		if(indb){
			if(e.action == 'm' && unchanged && !samemeta(db.d, e.d))
				conflict(e.path, "locally modified metadata", action(e.action));
			else
				conflict(e.path, "locally modified", action(e.action));
		}else{
			if(db != nil)
				conflict(e.path, "locally retained or recreated", action(e.action));	# server installed it but later removed it
			else
				conflict(e.path, "locally created", action(e.action));
		}
		return Skip;
	}
}

#TODO rewrite this to use hold
enact(e: ref Entry): int
{
	if(nflag)
		return 0;
#	srcfile := logs->mkpath(srvroot, e.serverpath);
	sha1 := hd e.contents;
	if(sha1 == nil || len sha1 != 40){
		warn("bad sha1");
		return 0;
	}
	srcfile := srvroot + "/" + sha1[0:2] + "/" + sha1[2:];
	dstfile := logs->mkpath(clientroot, e.path);
	case e.action {
	'a' =>	# create and copy in
		if(debug)
			sys->print("create %q\n", dstfile);
		if(e.d.mode & Sys->DMDIR)
			err := mkdir(dstfile, e);
		else
			err = copyin(srcfile, dstfile, 1, e);
		if(err != nil){
			if(noerr)
				error(err);
			warn(err);
			return 0;
		}
	'c' =>	# contents
		err := copyin(srcfile, dstfile, 0, e);
		if(err != nil){
			if(noerr)
				error(err);
			warn(err);
			return 0;
		}
	'd' =>	# delete
		if(debug)
			sys->print("remove %q\n", dstfile);
		if(remove(dstfile) < 0){
			warn(sys->sprint("can't remove %q: %r", dstfile));
			return 0;
		}
	'm' =>	# metadata
		if(debug)
			sys->print("wstat %q\n", dstfile);
		d := sys->nulldir;
		d.mode = e.d.mode;
		if(sys->wstat(dstfile, d) < 0)
			warn(sys->sprint("%q: can't change mode to %uo", dstfile, d.mode));
		if(setgid){
			d = sys->nulldir;
			d.gid = e.d.gid;
			if(sys->wstat(dstfile, d) < 0)
				warn(sys->sprint("%q: can't change gid to %q", dstfile, d.gid));
		}
		if(setuid){
			d = sys->nulldir;
			d.uid = e.d.uid;
			if(sys->wstat(dstfile, d) < 0)
				warn(sys->sprint("%q: can't change uid to %q", dstfile, d.uid));
		}
	* =>
		error(sys->sprint("unexpected log operation: %c %q", e.action, e.path));
		return 0;
	}
	return 1;
}

rev[T](l: list of T): list of T
{
	rl: list of T;
	for(; l != nil; l = tl l)
		rl = hd l :: rl;
	return rl;
}

ensure[T](m: T, path: string)
{
	if(m == nil)
		error(sys->sprint("can't load %s: %r", path));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: %s\n", s);
	raise "fail:error";
}

note(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: note: %s\n", s);
}

warn(s: string)
{
	sys->fprint(sys->fildes(2), "applylog: warning: %s\n", s);
	nerror++;
}

conflict(name: string, why: string, wont: string)
{
	sys->fprint(sys->fildes(2), "%q: %s; will not %s\n", name, why, wont);
	nconflict++;
}

action(a: int): string
{
	case a {
	'a' =>	return "create";
	'c' =>	return "update";
	'd' =>	return "delete";
	'm' =>	return "update metadata";
	* =>	return sys->sprint("unknown action %c", a);
	}
}

samecontents(path1, path2: string): int
{
	f1 := sys->open(path1, Sys->OREAD);
	if(f1 == nil)
		return 0;
	f2 := sys->open(path2, Sys->OREAD);
	if(f2 == nil)
		return 0;
	b1 := array[Sys->ATOMICIO] of byte;
	b2 := array[Sys->ATOMICIO] of byte;
	n := 256;	# start with something small; dis files and big executables should fail more quickly
	n1, n2: int;
	do{
		n1 = sys->read(f1, b1, n);
		n2 = sys->read(f2, b2, n);
		if(n1 != n2)
			return 0;
		for(i := 0; i < n1; i++)
			if(b1[i] != b2[i])
				return 0;
		n += len b1 - n;
	}while(n1 > 0);
	return 1;
}

samestat(a: Sys->Dir, b: Sys->Dir): int
{
	# doesn't check permission/ownership, does check QTDIR/QTFILE
	if(a.mode & Sys->DMDIR)
		return (b.mode & Sys->DMDIR) != 0;
	return a.length == b.length  && a.qid.qtype == b.qid.qtype;	# TO DO: && a.mtime == b.mtime a.name==b.name?
	# ignore mtime because it's always different for stowage. we check contents if we have it.
}

samemeta(a: Sys->Dir, b: Sys->Dir): int
{
	return a.mode == b.mode && (!setuid || a.uid == b.uid) && (!setgid || a.gid == b.gid) && samestat(a, b);
}

bigof(s: string, base: int): big
{
	(b, r) := str->tobig(s, base);
	if(r != nil)
		error("cruft in integer field in log entry: "+s);
	return b;
}

intof(s: string, base: int): int
{
	return int bigof(s, base);
}

mkdir(dstpath: string, e: ref Entry): string
{
	fd := create(dstpath, Sys->OREAD, e.d.mode);
	if(fd == nil)
		return sys->sprint("can't mkdir %q: %r", dstpath);
	fchmod(fd, e.d.mode);
	if(setgid)
		fchgrp(fd, e.d.gid);
	if(setuid)
		fchown(fd, e.d.uid);
#	e.d.mtime = now;
	return nil;
}

fchmod(fd: ref Sys->FD, mode: int)
{
	d := sys->nulldir;
	d.mode = mode;
	if(sys->fwstat(fd, d) < 0)
		warn(sys->sprint("%q: can't set mode %o: %r", sys->fd2path(fd), mode));
}

fchgrp(fd: ref Sys->FD, gid: string)
{
	d := sys->nulldir;
	d.gid = gid;
	if(sys->fwstat(fd, d) < 0)
		warn(sys->sprint("%q: can't set group id %s: %r", sys->fd2path(fd), gid));
}

fchown(fd: ref Sys->FD, uid: string)
{
	d := sys->nulldir;
	d.uid = uid;
	if(sys->fwstat(fd, d) < 0)
		warn(sys->sprint("%q: can't set user id %s: %r", sys->fd2path(fd), uid));
}

copyin(srcpath: string, dstpath: string, dowstat: int, e: ref Entry): string
{
	if(debug)
		sys->print("copyin %q -> %q\n", srcpath, dstpath);
	f := sys->open(srcpath, Sys->OREAD);
	if(f == nil)
		return sys->sprint("can't open %q: %r", srcpath);
	t: ref Sys->FD;
	(ok, nil) := sys->stat(dstpath);
	if(ok < 0){
		t = create(dstpath, Sys->OWRITE, e.d.mode | 8r222);
		if(t == nil)
			return sys->sprint("can't create %q: %r", dstpath);
		# TO DO: force access to parent directory
		dowstat = 1;
	}else{
		t = sys->open(dstpath, Sys->OWRITE|Sys->OTRUNC);
		if(t == nil){
			err := sys->sprint("%r");
			if(!contains(err, "permission"))
				return sys->sprint("can't overwrite %q: %s", dstpath, err);
		}
	}
	(nw, err) := gunzip(f, t);
	if(err != nil)
		return err;
	if(nw != e.d.length)
		warn(sys->sprint("%q: log said %bud bytes, copied %bud bytes", dstpath, e.d.length, nw));
	f = nil;
	if(dowstat){
		fchmod(t, e.d.mode);
		if(setgid)
			fchgrp(t, e.d.gid);
		if(setuid)
			fchown(t, e.d.uid);
	}
	nd := sys->nulldir;
	nd.mtime = e.d.mtime;
	if(sys->fwstat(t, nd) < 0)
		warn(sys->sprint("%q: can't set mtime: %r", dstpath));
	return nil;
}

copy(f: ref Sys->FD, t: ref Sys->FD): (big, string)
{
	buf := array[Sys->ATOMICIO] of byte;
	nw := big 0;
	while((n := sys->read(f, buf, len buf)) > 0){
		if(sys->write(t, buf, n) != n)
			return (nw, sys->sprint("error writing %q: %r", sys->fd2path(t)));
		nw += big n;
	}
	if(n < 0)
		return (nw, sys->sprint("error reading %q: %r", sys->fd2path(f)));
	return (nw, nil);
}

gunzip(in: ref Sys->FD, out: ref Sys->FD): (big, string)
{
	nw := big 0;
	rq := inflate->start("h");
	for(;;) {
		pick m := <-rq {
		Fill =>
			n := sys->read(in, m.buf, len m.buf);
			m.reply <-= n;
			if (n == -1) {
				return (nw, "read error");
			}
		Result =>
			if (len m.buf > 0) {
				n := sys->write(out, m.buf, len m.buf);
				if (n != len m.buf) {
					m.reply <-= -1;
					return (nw, "write error");
				}
				nw += big n;
				m.reply <-= 0;
			}
		#Info =>
		#	if m.msg begins with "file", it's the original filename of the compressed file.
		#	if m.msg begins with "mtime", it's the original modification time.
		Finished =>
			return (nw, nil);
		Error =>
#			sys->fprint(sys->fildes(2), "inflate error: %s\n", m.e);
			return (nw, "inflate error");
		}
	}
}

contents(e: ref Entry): string
{
	s := "";
	for(cl := e.contents; cl != nil; cl = tl cl)
		s += " " + hd cl;
	return s;
}

dumpstate()
{
	for(i := 0; i < client.nstate; i++)
		sys->print("%d\t%s\n", i, client.state[i].text());
}

dumpdb(db: ref Db, tag: int)
{
	for(i := 0; i < db.nstate; i++){
		if(!tag)
			s := db.state[i].dbtext();
		else
			s = db.state[i].text();
		if(s != nil)
			sys->print("%s\n", s);
	}
}

#
# perhaps these should be in a utility module
#
parent(name: string): string
{
	slash := -1;
	for(i := 0; i < len name; i++)
		if(name[i] == '/')
			slash = i;
	if(slash > 0)
		return name[0:slash];
	return "/";
}

writableparent(name: string): (int, string)
{
	p := parent(name);
	(ok, d) := sys->stat(p);
	if(ok < 0)
		return (-1, nil);
	nd := sys->nulldir;
	nd.mode |= 8r222;
	sys->wstat(p, nd);
	return (d.mode, p);
}

create(name: string, rw: int, mode: int): ref Sys->FD
{
	fd := sys->create(name, rw, mode);
	if(fd == nil){
		err := sys->sprint("%r");
		if(!contains(err, "permission")){
			sys->werrstr(err);
			return nil;
		}
		(pm, p) := writableparent(name);
		if(pm >= 0){
			fd = sys->create(name, rw, mode);
			d := sys->nulldir;
			d.mode = pm;
			sys->wstat(p, d);
		}
		sys->werrstr(err);
	}
	return fd;
}

remove(name: string): int
{
	if(sys->remove(name) >= 0)
		return 0;
	err := sys->sprint("%r");
	if(contains(err, "entry not found") || contains(err, "not exist"))
		return 0;
	(pm, p) := writableparent(name);
	rc := sys->remove(name);
	d := sys->nulldir;
	if(pm >= 0){
		d.mode = pm;
		sys->wstat(p, d);
	}
	sys->werrstr(err);
	return rc;
}

contains(s: string, sub: string): int
{
	return str->splitstrl(s, sub).t1 != nil;
}
