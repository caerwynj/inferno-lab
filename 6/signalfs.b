implement Signalfs;

#
# Copyright © 2003 Vita Nuova Holdings Limited.
#
# 2 level clone mechanism supporting multiple modules.
# filesystem looks like:
#	ctl
#	mod1
#		clone
#		1
#			ctl
#			data
#	mod2
#		clone
#		1
#			ctl
#			data


include "sys.m";
	sys: Sys;
	sprint, fprint: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;
	Enotdir, Enotfound: import Styxservers;
	nametree: Nametree;
include "signal.m";
include "arg.m";
	arg: Arg;

Signalfs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "signalfs: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

user := "me";
qidseq := 1;
stderr : ref Sys->FD;
debug := 1;
pidregister: chan of (int, int);
flush: chan of (int, int, chan of int);

makeconn: chan of (ref Mod, chan of (ref Conn, string));
delconn: chan of (ref Mod, ref Conn);
reqpool: list of chan of (ref Tmsg, ref Conn, ref Fid);
reqidle: int;
reqdone: chan of chan of (ref Tmsg, ref Conn, ref Fid);

srv: ref Styxserver;

mods: array of ref Mod;
nmods := 0;
configstr := "";

Qerror, Qtopdir, Qtopctl, Qmoddir, Qclone, Qconvdir, Qctl, Qdata: con iota;
Qtopbase: con Qtopctl;
Qconvbase: con Qctl;
Qmodbase: con Qclone;

Logtype: con 5;
Masktype: con (1<<Logtype) - 1;
Logconv: con 12;
Maskconv: con (1<<Logconv) - 1;
Shiftconv: con Logtype;
Logmod: con 8;
Maskmod: con (1<<Logmod) - 1;
Shiftmod: con (Logtype + Logconv);

Maxreqidle: con 3;
Maxreplyidle: con 3;

Idle, Inuse: con iota;

Conn: adt {
	signal:	Signal;
	n:		int;
	nreads:	int;
	state:	int;
};

Mod: adt {
	path:		string;
	name:	string;
	conns:	array of ref Conn;
	nconns:	int;			# number of conversations
	qid:		int;			# qid for mod directory
};

TYPE(path: int): int
{
	return path & Masktype;
}
CONV(path: int): int
{
	return (path>>Shiftconv) & Maskconv;
}
MOD(path:int): int
{
	return (path>>Shiftmod) & Maskmod;
}
QID(m, c, y: int): int
{
	return ((m<<Shiftmod) | (c<<Shiftconv)) | y;
}

usage()
{
	sys->fprint(sys->fildes(2), "modfs mod.dis\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	styx->init();
	stderr = sys->fildes(2);
	sys->pctl(Sys->NEWPGRP, nil);	
	arg = load Arg Arg->PATH;
	arg->setusage("modfs [-a|-b|-ac|-bc] [-D]  mountpoint");
	arg->init(argv);
	flags := Sys->MREPL;
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'D' =>	styxservers->traceset(1);
		* =>		arg->usage();
		}
	argv = arg->argv();
	if(len argv != 1)
		arg->usage();
	mountpt := hd argv;
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		fprint(stderr, "can't create pipe: %r");
		exit;
	}
	config("");
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);


	navops := chan of ref Navop;
	spawn navigator(navops);
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(fds[0], Navigator.new(navops), big Qtopdir);
	srv.replychan = chan of ref Styx->Rmsg;
	spawn replymarshal(srv.replychan);
	fds[0] = nil;
	pidc := chan of int;
	spawn serve(tchan, navops, pidc);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, flags, nil) < 0)
		fprint(stderr, "can't mount modfs: %r");
}

serve(tchan: chan of ref Tmsg, navops: chan of ref Navop, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	pidregister = chan of (int, int);
	makeconn = chan of (ref Mod, chan of (ref Conn, string));
	delconn = chan of (ref Mod, ref Conn);
	flush = chan of (int, int, chan of int);
	reqdone = chan of chan of (ref Tmsg, ref Conn, ref Fid);
	spawn flushproc(flush);

Serve:
	for(;;)alt{
	gm := <-tchan =>
		if(gm == nil)
			break Serve;
		pick m := gm {
		Readerror =>
			sys->fprint(sys->fildes(2), "wmexport: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			(fid, mode, d, err) := srv.canopen(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.default(m);
			else
				request(m, fid);
		Read =>
			(fid, err) := srv.canread(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.read(m);
			else
				request(m, fid);
		Write =>
			(fid, err) := srv.canwrite(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else
				request(m, fid);
		Flush =>
			done := chan of int;
			flush <-= (m.tag, m.oldtag, done);
			<-done;
		Clunk =>
			request(m, srv.clunk(m));
		* =>
			srv.default(gm);
		}
	(m, rc) := <-makeconn =>
		for(i:=0; i < m.nconns; i++)
			if(m.conns[i].state == Idle){
				m.conns[i].state = Inuse;
				m.conns[i].nreads = 0;
				rc <-= (m.conns[i], nil);
				break;
			}
		if(i == m.nconns) {
			if(m.nconns >= len m.conns)
				m.conns = (array[len m.conns + 5] of ref Conn)[0:] = m.conns;
			sig := load Signal m.path;
			if(sig == nil) {
				fprint(stderr, "bad module %s\n", m.path);
				rc <-= (nil, nil);
			}else{
				sig->init(nil);
				c := ref Conn(sig, qidseq++, 0, Inuse);
				m.conns[m.nconns++] = c;
				rc <-= (c, nil);
			}
		}
	(m, c) := <-delconn =>
		for(i := 0; i < m.nconns; i++)
			if(m.conns[i] == c){
				m.conns[i].state = Idle;
				break;
			}
#		m.nconns--;
#		if(i < m.nconns)
#			m.conns[i] = m.conns[m.nconns];
#		m.conns[m.nconns] = nil;
	reqpool = <-reqdone :: reqpool =>
		if(reqidle++ > Maxreqidle){
			hd reqpool <-= (nil, nil, nil);
			reqpool = tl reqpool;
			reqidle--;
		}
	}
	navops <-= nil;
}

request(m: ref Styx->Tmsg, fid: ref Fid)
{
	path := int fid.path;
	conn: ref Conn;
	case TYPE(path) {
	Qctl or Qdata =>
		mod := mods[MOD(path)];
		n := CONV(path);
		for(i := 0; i < mod.nconns; i++){
			if(mod.conns[i].n == n){
				conn = mod.conns[i];
				break;
			}
		}
	};
	c: chan of (ref Tmsg, ref Conn, ref Fid);
	if(reqpool == nil){
		c = chan of (ref Tmsg, ref Conn, ref Fid);
		spawn requestproc(c);
	}else{
		(c, reqpool) = (hd reqpool, tl reqpool);
		reqidle--;
	}
	c <-= (m, conn, fid);
}

requestproc(req: chan of (ref Tmsg, ref Conn, ref Fid))
{
	pid := sys->pctl(0, nil);
	for(;;){
		(gm, c, fid) := <-req;
		if(gm == nil)
			break;
		pidregister <-= (pid, gm.tag);
		path := int fid.path;
		pick m := gm {
		Read =>
			case TYPE(path) {
			Qtopctl =>
				srv.replydirect(styxservers->readstr(m , configstr));
			Qctl =>
				if(c == nil)
					srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
				# first read gets number of connection.
				else if(c.nreads++ == 0)
					srv.replydirect(styxservers->readstr(m, string c.n));
				else
					srv.replydirect(styxservers->readstr(m, c.signal->configstr));
			Qdata =>
				if(c == nil)
					srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
				else
					srv.replydirect(ref Rmsg.Read(m.tag, c.signal->read(m.count)));;
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking1?"));
			}
		Write =>
			case TYPE(path) {
			Qtopctl =>
				if((s := config(string m.data)) == nil)
					srv.replydirect(ref Rmsg.Write(m.tag, len m.data));
				else
					srv.replydirect(ref Rmsg.Error(m.tag, s));
			Qctl =>
				if(c == nil)
					srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
				else{
					if((s := c.signal->config(string m.data)) == nil)
						srv.replydirect(ref Rmsg.Write(m.tag, len m.data));
					else
						srv.replydirect(ref Rmsg.Error(m.tag, s));
				}
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking2?"));
			}
		Open =>
			if(c == nil && TYPE(path) != Qclone && TYPE(path) != Qtopctl)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			err: string;
			q := qid(path);
			case TYPE(path) {
			Qclone =>
				cch := chan of (ref Conn, string);
				makeconn <-= (mods[MOD(path)], cch);
				(c, err) = <-cch;
				if(c != nil)
					q = qid(QID(MOD(path), c.n, Qctl));
			Qdata =>
				;
			Qctl =>
				if(c.state == Inuse)
					err = "in use";
				else
					c.state = Inuse;
			Qtopctl =>
				;
			* =>
				err = "what was i thinking3?";
			}
			if(err != nil)
				srv.replydirect(ref Rmsg.Error(m.tag, err));
			else{
				srv.replydirect(ref Rmsg.Open(m.tag, q, 0));
				fid.open(m.mode, q);
			}
		Clunk =>
			case TYPE(path) {
			Qctl =>
				if(c != nil)
					delconn <-= (mods[MOD(path)], c);
			}
		* =>
			srv.replydirect(ref Rmsg.Error(gm.tag, "oh dear"));	
		}
		pidregister <-= (pid, -1);
		reqdone <-= req;
	}
}

qid(path: int): Sys->Qid
{
	return dirgen(path).t0.qid;
}
		
replyproc(c: chan of ref Rmsg, replydone: chan of chan of ref Rmsg)
{
	# hmm, this could still send a reply out-of-order with a flush
	while((m := <-c) != nil){
		srv.replydirect(m);
		replydone <-= c;
	}
}

# deal with reply messages coming from styxservers.
replymarshal(c: chan of ref Styx->Rmsg)
{
	replypool: list of chan of ref Rmsg;
	n := 0;
	replydone := chan of chan of ref Rmsg;
	for(;;) alt{
	m := <-c =>
		c: chan of ref Rmsg;
		if(replypool == nil){
			c = chan of ref Rmsg;
			spawn replyproc(c, replydone);
		}else{
			(c, replypool) = (hd replypool, tl replypool);
			n--;
		}
		c <-= m;
	replypool = <-replydone :: replypool =>
		if(++n > Maxreplyidle){
			hd replypool <-= nil;
			replypool = tl replypool;
			n--;
		}
	}
}

navigator(navops: chan of ref Navop)
{
	while((m := <-navops) != nil){
		path := int m.path;
		pick n := m {
		Stat =>
			n.reply <-= dirgen(int n.path);
		Walk =>
			name := n.name;
			case TYPE(path) {
			Qconvdir =>
				dp := CONV(path);
				case name {
				".." =>
					path = QID(MOD(path), 0, Qmoddir);
				"ctl" =>
					path = QID(MOD(path), CONV(path), Qctl);
				"data" =>
					path = QID(MOD(path), CONV(path), Qdata);
				* =>
					path = Qerror;
				}
			Qmoddir =>
				case name{
				".." =>
					path = QID(0, 0, Qtopdir);
				"clone" =>
					path = QID(MOD(path), 0, Qclone);
				* =>
					x := int name;
					k := MOD(path);
					path = Qerror;
					mod := mods[k];
					if(string x == name){
						for(i := 0; i < mod.nconns; i++)
							if(mod.conns[i].n == x){
								path = QID(k, x, Qconvdir);
								break;
							}
					}
				}
			Qtopdir =>
				case name {
				"ctl" =>
					path = Qtopctl;
				* =>
					path = Qerror;
					for(i := 0; i < nmods; i++)
						if(mods[i].name == name){
							path = QID(i, 0, Qmoddir);
							break;
						}
				}
			}
			n.reply <-= dirgen(path);
		Readdir =>
			err := "";
			d: array of int;
			case TYPE(path) {
			Qconvdir =>
				d = array[2] of int;;
				d[0] = QID(MOD(path), CONV(path), Qctl);
				d[1] = QID(MOD(path), CONV(path), Qdata);
			Qmoddir =>
				mod := mods[MOD(path)];
				d = array[mod.nconns + 1] of int;
				d[0] = Qclone;
				for(i := 0; i < mod.nconns; i++)
					d[i + 1] = QID(MOD(path), mod.conns[i].n, Qconvdir);
			Qtopdir =>
				d = array[nmods + 1] of int;
				d[0] = QID(0, 0, Qtopctl);
				for(i := 0; i < nmods; i++)
					d[i + 1] = QID(i, 0, Qmoddir);
			}
			if(d == nil){
				n.reply <-= (nil, Enotdir);
				break;
			}
			for (i := n.offset; i < len d && i < n.count; i++)
				n.reply <-= dirgen(d[i]);
			n.reply <-= (nil, nil);
		}
	}
}

dirgen(path: int): (ref Sys->Dir, string)
{
	name: string;
	perm: int;
	case TYPE(path) {
	Qtopdir =>
		name = ".";
		perm = 8r555|Sys->DMDIR;
	Qmoddir =>
		name = mods[MOD(path)].name;
		perm = 8r555|Sys->DMDIR;
	Qconvdir =>
		name = string CONV(path);
		perm = 8r555|Sys->DMDIR;
	Qtopctl =>
		name = "ctl";
		perm = 8r666;
	Qclone =>
		name = "clone";
		perm = 8r666;
	Qctl =>
		name = "ctl";
		perm = 8r666;
	Qdata =>
		name = "data";
		perm = 8r444;
	Qerror =>
		fprint(stderr, "error type\n");
		return (nil, Enotfound);
	* =>
		fprint(stderr, "type not found\n");
		return (nil, Enotfound);
	}
	return (dir(path, name, perm), nil);
}

dir(path: int, name: string, perm: int): ref Sys->Dir
{
	d := ref sys->zerodir;
	d.qid.path = big path;
	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	d.mode = perm;
	d.name = name;
	d.uid = user;
	d.gid = user;
	return d;
}

flushproc(flush: chan of (int, int, chan of int))
{
	a: array of (int, int);
	n := 0;
	for(;;)alt{
	(pid, tag) := <-pidregister =>
		if(tag == -1){
			for(i := 0; i < n; i++)
				if(a[i].t0 == pid)
					break;
			n--;
			if(i < n)
				a[i] = a[n];
		}else{
			if(n >= len a){
				na := array[n + 5] of (int, int);
				na[0:] = a;
				a = na;
			}
			a[n++] = (pid, tag);
		}
	(tag, oldtag, done) := <-flush =>
		for(i := 0; i < n; i++)
			if(a[i].t1 == oldtag){
				spawn doflush(tag, a[i].t0, done);
				break;
			}
		if(i == n)
			spawn doflush(tag, -1, done);
	}
}

doflush(tag: int, pid: int, done: chan of int)
{
	if(pid != -1){
		kill(pid, "kill");
		pidregister <-= (pid, -1);
	}
	srv.replydirect(ref Rmsg.Flush(tag));
	done <-= 1;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

config(s: string): string
{
	(n, flds) := sys->tokenize(s, " \t\n\r");
	if(flds != nil){
		case hd flds {
		"add" =>
			if(len flds != 3)
				return "error: invalid message";
			if(nmods >= len mods)
				mods = (array[len mods + 5] of ref Mod)[0:] = mods;
			mods[nmods] = ref Mod;
			mods[nmods].path = hd tl flds;
			mods[nmods].name = hd tl tl flds;
			mods[nmods].nconns = 0;
			nmods++;
		}
	}
	configstr = "";
	for(i:=0; i<nmods;i++)
		configstr += sprint("%s %s\n", mods[i].path, mods[i].name);
	return nil;
}
