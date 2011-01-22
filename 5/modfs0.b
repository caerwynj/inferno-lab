implement Modfs;

#
# Copyright © 2003 Vita Nuova Holdings Limited.
#

include "sys.m";
	sys: Sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;
	Enotdir, Enotfound: import Styxservers;
	nametree: Nametree;
include "ffs.m";

Modfs: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

# filesystem looks like:
#	clone
#	1
#		ctl
#		data

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "modfs: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

user := "me";
qidseq := 1;
ffsmod := "";

pidregister: chan of (int, int);
flush: chan of (int, int, chan of int);

makeconn: chan of chan of (ref Conn, string);
delconn: chan of ref Conn;
reqpool: list of chan of (ref Tmsg, ref Conn, ref Fid);
reqidle: int;
reqdone: chan of chan of (ref Tmsg, ref Conn, ref Fid);

srv: ref Styxserver;

conns: array of ref Conn;
nconns := 0;

Qerror, Qroot, Qdir, Qclone, Qctl, Qdata: con iota;
Shift: con 4;
Mask: con 16rf;

Maxreqidle: con 3;
Maxreplyidle: con 3;

Conn: adt {
	ffs:		Ffs;
	n:		int;
	nreads:	int;
};

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

	argv = tl argv;
	if(argv == nil)
		usage();
	ffsmod = hd argv;
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);

	sys->pctl(Sys->FORKNS, nil);		# fork pgrp?

	navops := chan of ref Navop;
	spawn navigator(navops);
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(navops), big Qroot);
	srv.replychan = chan of ref Styx->Rmsg;
	spawn replymarshal(srv.replychan);
	spawn serve(tchan, navops);
}

serve(tchan: chan of ref Tmsg, navops: chan of ref Navop)
{
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
	rc := <-makeconn =>
		if(nconns >= len conns)
			conns = (array[len conns + 5] of ref Conn)[0:] = conns;
		ffs := load Ffs ffsmod;
		ffs->init(nil);
		c := ref Conn(ffs, qidseq++, 0);
		conns[nconns++] = c;
		rc <-= (c, nil);
	c := <-delconn =>
		for(i := 0; i < nconns; i++)
			if(conns[i] == c)
				break;
		nconns--;
		if(i < nconns)
			conns[i] = conns[nconns];
		conns[nconns] = nil;
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
				# first read gets number of connection.
#				m.offset = big 0;
				if(c.nreads++ == 0)
					srv.replydirect(styxservers->readstr(m, string c.n));
				else
					srv.replydirect(styxservers->readstr(m, c.ffs->configstr));
			Qdata =>
				srv.replydirect(ref Rmsg.Read(m.tag, c.ffs->read(m.count)));;
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking1?"));
			}
		Write =>
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qctl =>
				c.ffs->config(string m.data);
				srv.replydirect(ref Rmsg.Write(m.tag, len m.data));
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
			Qdata =>
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
				"data" =>
					path = Qdata | dp;
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
			err := "";
			d: array of int;
			case path & Mask {
			Qdir =>
				d = array[] of {Qctl, Qdata};
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
	Qdata =>
		name = "data";
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

# return number of characters from s that will fit into
# max bytes when encoded as utf-8.
fullutf(s: string, max: int): int
{
	Bit1:	con 7;
	Bitx:	con 6;
	Bit2:	con 5;
	Bit3:	con 4;
	Bit4:	con 3;
	Rune1:	con (1<<(Bit1+0*Bitx))-1;		# 0000 0000 0111 1111
	Rune2:	con (1<<(Bit2+1*Bitx))-1;		# 0000 0111 1111 1111
	Rune3:	con (1<<(Bit3+2*Bitx))-1;		# 1111 1111 1111 1111
	nb := 0;
	for(i := 0; i < len s; i++){
		c := s[i];
		if(c <= Rune1)
			nb++;
		else if(c <= Rune2)
			nb += 2;
		else
			nb += 3;
		if(nb > max)
			break;
	}
	return i;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
