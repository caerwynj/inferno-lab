implement Masterfs;

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
include "readdir.m";
	readdir: Readdir;
include "arg.m";
	arg: Arg;
include "sh.m";
	sh: Sh;

Masterfs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

# filesystem looks like:
#	clone
#	1
#		ctl
#		status

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "masterfs: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

user := "me";
qidseq := 1;
imgseq := 0;

pidregister: chan of (int, int);
flush: chan of (int, int, chan of int);

makeconn: chan of chan of (ref Conn, string);
delconn: chan of ref Conn;
reqpool: list of chan of (ref Tmsg, ref Conn, ref Fid);
reqidle: int;
reqdone: chan of chan of (ref Tmsg, ref Conn, ref Fid);

srv: ref Styxserver;
stderr: ref Sys->FD;

conns: array of ref Conn;
nconns := 0;

Qerror, Qroot, Qdir, Qclone, Qctl, Qstatus: con iota;
Shift: con 4;
Mask: con 16rf;

Maxreqidle: con 3;
Maxreplyidle: con 3;

Map, Reduce: con iota;
mcnt, rcnt: int;
mxcnt: int;

M := 1;
R := 7;

# Connection to a worker
Conn: adt {
	n:		int;
	nreads:	int;
	filechan: chan of (string, big);
	filelst : list of (string, big);
	wtype:	int;
	msplit:	int;			# /tmp/mr.node.pid.msplit.rsplit
	host:		string;		# tcp!host
};

filechan: chan of (string, big);
rchan: array of chan of (string, big);   #R chans 
mountpt := "/mnt/mapreduce";
mapmod: string;
redmod: string;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);
	readdir = load Readdir Readdir->PATH;
	stderr = sys->fildes(2);
	sys->pctl(Sys->NEWPGRP, nil);		# fork pgrp?
	
	arg = load Arg Arg->PATH;
	arg->setusage("mapreduce [-a|-b|-ac|-bc] [-D]  [-m mountpoint] mapper reducer path ...");
	arg->init(argv);
	flags := Sys->MREPL;
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'D' =>	styxservers->traceset(1);
		'm' =>	mountpt = arg->earg();
		'M' =>	M = int arg->earg();
		'R' =>	R = int arg->earg();
		* =>		arg->usage();
		}
	argv = arg->argv();
	if(len argv < 3)
		arg->usage();
	mapmod = hd argv;
	redmod = hd tl argv;
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0){
		fprint(stderr, "can't create pipe: %r");
		exit;
	}
	navops := chan of ref Navop;
	spawn navigator(navops);
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(fds[0], Navigator.new(navops), big Qroot);
	srv.replychan = chan of ref Styx->Rmsg;
	spawn replymarshal(srv.replychan);
	fds[0] = nil;
	pidc := chan of int;
	spawn serve(tchan, navops, pidc);
	<-pidc;

	filechan = chan of (string, big);
	rchan = array[R] of {* => chan[10] of (string, big)};
	
	if(sys->mount(fds[1], nil, mountpt, flags, nil) < 0)
		fprint(stderr, "can't mount mapreduce: %r");

	argv = tl tl argv;
	for(; argv != nil; argv = tl argv)
		spawn du(hd argv);
	#TODO: split files over a threshold
	# du can just divy out the files as fast as workers can read them.
	# run cpu with workers for M split.
	# monitor that a worker completes else restart another worker
	# once all map workers are complete build the filelists for the reduce workers
	# start R reduceworkers using cpu
	# reduce workers can be started at same time as map workers. they have
	# to wait reading for records though.
	# keep track of what we sent to a client so we can restart.
	# we could have each worker write back the number of bytes it processed
	# from a file, so we know if it closed without writing back we need to
	# restart.
	
	# Launch workers
	# spawn exec("cpu" :: "tcp!localhost" :: "worker" :: nil);
	# for(i := 0; i < M + R; i++)
	#	spawn worker(mountpt + "/clone");
}

serve(tchan: chan of ref Tmsg, navops: chan of ref Navop, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	pidregister = chan of (int, int);
	makeconn = chan of chan of (ref Conn, string);
	delconn = chan of ref Conn;
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
			sys->fprint(sys->fildes(2), "mapreduce: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			(fid, nil, nil, err) := srv.canopen(m);
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
	rc := <-makeconn =>
		if(nconns >= len conns)
			conns = (array[len conns + 5] of ref Conn)[0:] = conns;
			
		# decide whether this is a map worker or a reduce worker
		# and select filechan appropriately
		if(mcnt < M)
			c := ref Conn(qidseq++, 0, filechan, nil, Map, mcnt++, nil);
		else
			c = ref Conn(qidseq++, 0, rchan[rcnt], nil, Reduce, rcnt++, nil);
		conns[nconns++] = c;
		rc <-= (c, nil);
	c := <-delconn =>
		for(i := 0; i < nconns; i++)
			if(conns[i] == c)
				break;
		# TODO: if this is a Map hand all the files off to a reducer
		if(c.wtype == Map){
			for(j := 0; j < R; j++)
				rchan[j] <-= ("/tmp/mapred." + string c.n + "." + string j, big 0);
			mxcnt++;
			if(mcnt == mxcnt){
				for(j = 0; j < R; j++)
					rchan[j] <-= (nil, big 0);
			}
		}
		nconns--;
		if(i < nconns)
			conns[i] = conns[nconns];
		conns[nconns] = nil;
		#TODO: last worker closed; check everything complete
		if(nconns == 0 &&  rcnt == R)
			break Serve;
	reqpool = <-reqdone :: reqpool =>
		if(reqidle++ > Maxreqidle){
			hd reqpool <-= (nil, nil, nil);
			reqpool = tl reqpool;
			reqidle--;
		}
	}
	navops <-= nil;
	sys->print("mapreduce done\n");
	kill(sys->pctl(0, nil), "killgrp");
	sys->unmount(nil, mountpt);
}

request(m: ref Styx->Tmsg, fid: ref Fid)
{
	n := int fid.path >> Shift;
	conn: ref Conn;
	for(i := 0; i < nconns; i++){
		if(conns[i].n == n){
			conn = conns[i];
			break;
		}
	}
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
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qctl =>
				# first read gets: WorkerType MorRsplit R module.dis
				m.offset = big 0;
				if(c.nreads++ == 0){
					if(c.wtype == Map)
						srv.replydirect(styxservers->readstr(m, 
							sprint("worker -m -R %d -d %s -i %d\n", R, mapmod, c.n)));
					else
						srv.replydirect(styxservers->readstr(m,
							sprint("worker -r -R %d -d %s -i %d\n", R, redmod, c.n)));
				}else{
					(name, length) :=<- c.filechan;
					if(name != nil){
						c.filelst = (name,length) :: c.filelst;
						srv.replydirect(styxservers->readstr(m, sys->sprint("%s %d %bd\n", name, 0, length)));
					}else{
						srv.replydirect(ref Rmsg.Read(m.tag, array[0] of byte));
					}
				}
			Qstatus =>
				srv.replydirect(styxservers->readstr(m, sys->sprint("%d\n", c.nreads)));
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking1?"));
			}
		Write =>
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qctl =>
				;
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking2?"));
			}
		Open =>
			if(c == nil && path != Qclone)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			err: string;
			q := qid(path);
			case path & Mask {
			Qclone =>
				cch := chan of (ref Conn, string);
				makeconn <-= cch;
				(c, err) = <-cch;
				if(c != nil)
					q = qid(Qctl | (c.n << Shift));
			Qstatus =>
				;
			Qctl =>
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
			case path & Mask {
			Qctl =>
				if(c != nil)
					delconn <-= c;
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
			case path & Mask {
			Qdir =>
				dp := path & ~Mask;
				case name {
				".." =>
					path = Qroot;
				"ctl" =>
					path = Qctl | dp;
				"status" =>
					path = Qstatus | dp;
				* =>
					path = Qerror;
				}
			Qroot =>
				case name{
				"clone" =>
					path = Qclone;
				* =>
					x := int name;
					path = Qerror;
					if(string x == name){
						for(i := 0; i < nconns; i++)
							if(conns[i].n == x){
								path = (x << Shift) | Qdir;
								break;
							}
					}
				}
			}
			n.reply <-= dirgen(path);
		Readdir =>
			d: array of int;
			case path & Mask {
			Qdir =>
				d = array[] of {Qctl, Qstatus};
				for(i := 0; i < len d; i++)
					d[i] |= path & ~Mask;
			Qroot =>
				d = array[nconns + 1] of int;
				d[0] = Qclone;
				for(i := 0; i < nconns; i++)
					d[i + 1] = (conns[i].n<<Shift) | Qdir;
			}
			if(d == nil){
				n.reply <-= (nil, Enotdir);
				break;
			}
			for (i := n.offset; i < len d; i++)
				n.reply <-= dirgen(d[i]);
			n.reply <-= (nil, nil);
		}
	}
}

dirgen(path: int): (ref Sys->Dir, string)
{
	name: string;
	perm: int;
	case path & Mask {
	Qroot =>
		name = ".";
		perm = 8r555|Sys->DMDIR;
	Qdir =>
		name = string (path >> Shift);
		perm = 8r555|Sys->DMDIR;
	Qclone =>
		name = "clone";
		perm = 8r666;
	Qctl =>
		name = "ctl";
		perm = 8r666;
	Qstatus =>
		name = "status";
		perm = 8r444;
	* =>
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

# Avoid loops in tangled namespaces.
NCACHE: con 1024; # must be power of two
cache := array[NCACHE] of list of ref sys->Dir;

seen(dir: ref sys->Dir): int
{
	h := int dir.qid.path & (NCACHE-1);
	for(c := cache[h]; c!=nil; c = tl c){
		t := hd c;
		if(dir.qid.path==t.qid.path && dir.dtype==t.dtype && dir.dev==t.dev)
			return 1;
	}
	cache[h] = dir :: cache[h];
	return 0;
}

dudir(dirname: string): big
{
	prefix := dirname+"/";
	if(dirname==".")
		prefix = nil;
	sum := big 0;
	(de, nde) := readdir->init(dirname, readdir->NAME);
	if(nde < 0)
		warn("can't read", dirname);
	for(i := 0; i < nde; i++) {
		s := prefix+de[i].name;
		if(de[i].mode & Sys->DMDIR){
			if(!seen(de[i])){	# arguably should apply to files as well
				size := dudir(s);
				sum += size;
			}
		}else{
			l := de[i].length;
			sum += l;
			add(s,  l);
		}
	}
	return sum;
}

du(name: string)
{
	(rc, d) := sys->stat(name);
	if(rc < 0){
		warn("can't stat", name);
	}else if(d.mode & Sys->DMDIR){
		d.length = dudir(name);
	}else
		add(name, d.length);
	for(;;)
		filechan <-= (nil, big 0);
}

warn(why: string, f: string)
{
	sys->fprint(sys->fildes(2), "mapred: %s %q: %r\n", why, f);
}

add(name: string, size: big)
{
	filechan <-= (name, size);
}

worker(mnt: string)
{
	c := load Command "/dis/mapreduce/worker.dis";
	if(c == nil){
		warn("worker", "you can't touch dis! da da-da dum");
		return;
	}
	
	c->init(nil, "worker" :: mnt :: nil);
}
