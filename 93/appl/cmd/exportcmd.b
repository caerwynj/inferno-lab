implement Cmdexport;
#
# cmdfs - synthetic file system interface to command execution
# 
# usage: mount {cmdfs} /n/cmd
#
# Based on telcofs code:
# Copyright © 2003 Vita Nuova Holdings Limited.
#

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;

include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Fid, Navigator, Navop: import styxservers;
	Enotdir, Enotfound: import Styxservers;
	nametree: Nametree;
include "sh.m";
	sh: Sh;
Cmdexport: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

# filesystem looks like:
#	clone
#	1
#		ctl
#		stderr
#		data
#		status
#		wait

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "cmdexport: cannot load %s: %r\n", p);
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
ctxt: ref Draw->Context;

conns: array of ref Conn;
nconns := 0;

Qerror, Qroot, Qdir, Qclone, Qctl, Qdata, Qstderr, Qstatus, Qwait: con iota;
Shift: con 4;
Mask: con 16rf;

Maxreqidle: con 3;
Maxreplyidle: con 3;

#
# Conn - per session data (copied from devcmd?)
# n: number of session (also directory name)
# nreads: number of people reading?
# wdir: ?
# fds: array of pipes for stdin, stdout, and stderr
# pid: resulting process id?
# killonclose: whether we kill this thread on closing the cmd
# nice: process priority
#

Conn: adt {
	n:		int;
	nreads:	int;
	wdir: string;
	fds: array of array of ref Sys->FD;
	pid: int;
	killonclose: int;
	nice: int;
};

cn(path: int): int
{
	return (path & ~Mask) >> Shift;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;

	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);
	sh = load Sh Sh->PATH;
	if(sh == nil)
		badmodule(Sh->PATH);

	sys->pctl(Sys->FORKNS, nil);		# fork pgrp?

	navops := chan of ref Navop;
	spawn navigator(navops);
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(navops), big Qroot);
	srv.replychan = chan of ref Styx->Rmsg;
	spawn replymarshal(srv.replychan);
	spawn serve(tchan, navops);
}

#
# multithreaded styx server dispatch
# also filters out directory ops to default mechanisms
#
# This also has a section maintaining connection creation & deletion
#

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
			sys->fprint(sys->fildes(2), "cmdexport: fatal read error: %s\n", m.error);
			break Serve;
		Open =>
			(fid, nil, nil, err) := srv.canopen(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.default(m);
			else
				request(ctxt, m, fid);
		Read =>
			(fid, err) := srv.canread(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else if(fid.qtype & Sys->QTDIR)
				srv.read(m);
			else
				request(ctxt, m, fid);
		Write =>
			(fid, err) := srv.canwrite(m);
			if(err != nil)
				srv.reply(ref Rmsg.Error(m.tag, err));
			else
				request(ctxt, m, fid);
		Flush =>
			done := chan of int;
			flush <-= (m.tag, m.oldtag, done);
			<-done;
		Clunk =>
			request(ctxt, m, srv.clunk(m));
		* =>
			srv.default(gm);
		}
	rc := <-makeconn =>
		if(nconns >= len conns)
			conns = (array[len conns + 5] of ref Conn)[0:] = conns;
		conns[nconns]=ref Conn(nconns, 0, "", array[3] of { * => array[2] of { * => ref Sys->FD}}, -1, 0, 1);
		rc <-= (conns[nconns], nil);
		nconns++;
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

#
# request - issue request to the pool, or spawn new thread to handle
#

request(nil: ref Draw->Context, m: ref Styx->Tmsg, fid: ref Fid)
{
	n := int fid.path >> Shift;
	conn: ref Conn;
	for(i := 0; i < nconns; i++)
		if(conns[i].n == n){
			conn = conns[i];
			break;
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

#
# requestproc - handle the actual request
#
# NOTE: This function is a bit of a clusterfuck at the moment
#

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
				if(m.offset != big 0)
					srv.replydirect(styxservers->readstr(m, nil));
				if(c.nreads++ == 0)
					srv.replydirect(styxservers->readstr(m, string c.n));
				srv.replydirect(styxservers->readstr(m, "hello from ctl file\n"));

				# what else do we need here?
			Qdata =>
				buf := array[8192] of byte;
				if(conns[cn(path)].fds[1][1] == nil)
					raise "fail: no fd";
				n := sys->read(conns[cn(path)].fds[1][1], buf, len buf);
				if(n >= 0)
					sys->print("buf %s n %d\n", string buf[:n], n);
				if(n > 0)
					srv.replydirect(styxservers->readbytes(m, buf[:n]));
				else if(n == 0)
					srv.replydirect(styxservers->readbytes(m, nil));
				else
					srv.replydirect(ref Rmsg.Error(m.tag, "failed read on data"+string n));

			Qstderr =>
				buf := array[8192] of byte;
				n := sys->read(conns[cn(path)].fds[2][0], buf, len buf);
				if(n > 0)
					srv.replydirect(styxservers->readbytes(m, buf[:n]));
				else if(n == 0)
					srv.replydirect(styxservers->readbytes(m, nil));
				else
					srv.replydirect(ref Rmsg.Error(m.tag, "failed read on stderr"));
			Qstatus =>
				if(m.offset != big 0)
					srv.replydirect(styxservers->readstr(m, nil));
				srv.replydirect(styxservers->readstr(m, "fill this in\n"));
			Qwait =>
				# what do I need to do here?
				# the conn should have the pid.
				# 
				sys->print("opening %s", "/prog/"+string c.pid+"/wait");
				wfd := sys->open("/prog/"+string c.pid+"/wait", Sys->OREAD);
				buf := array[64] of byte;
				n := sys->read(wfd, buf, len buf);
				# open the wait file of the prog
				# read from it.
				# reply with the status
				if(n > 0)
					srv.replydirect(styxservers->readstr(m, string buf[:n]));
				else
					srv.replydirect(ref Rmsg.Error(m.tag, "couldn't read wait file"));
			* =>
				srv.replydirect(ref Rmsg.Error(m.tag, "what was i thinking1?"));
			}
		Write =>
			if(c == nil)
				srv.replydirect(ref Rmsg.Error(m.tag, "connection is dead"));
			case path & Mask {
			Qctl =>
				(nil, l) := sys->tokenize(string m.data, " \t");
				case hd l {
				"dir" =>
					l = tl l;
					if(len l  != 1)
						srv.replydirect(ref Rmsg.Error(m.tag, "dir takes 1 argument"));
					conns[cn(path)].wdir = hd l;
				"exec" =>
					l = tl l;
				#	if(len l  < 2)
				#		srv.replydirect(ref Rmsg.Error(m.tag, "exec needs 2+ args"));
					sys->print("exec cn(path) %d\n", cn(path));
					fd := conns[cn(path)].fds;

					sys->write(fd[1][0], array of byte "primed data", 11);
					sys->write(fd[2][0], array of byte "primed err", 10);
					pc := chan of int;
					spawn spawner(pc, l, fd);
					conns[cn(path)].pid = <- pc;
					sys->print("/prog/%d\n", conns[cn(path)].pid);
				"kill" =>
					l = tl l;
					if(len l  != 0)
						srv.replydirect(ref Rmsg.Error(m.tag, "kill doesn't take any arguments"));
					# any other bookkeeping here?
					kill(conns[cn(path)].pid, "kill");
				"killonclose" =>
					l = tl l;
					if(len l  != 0)
						srv.replydirect(ref Rmsg.Error(m.tag, "killonclose doesn't take any arguments"));
					conns[cn(path)].killonclose = 1;	
				"nice" =>
					l = tl l;
					if(len l  > 1)
						srv.replydirect(ref Rmsg.Error(m.tag, "dir takes <=1 arguments"));
					if(l == nil)
						conns[cn(path)].nice = 1;
					conns[cn(path)].nice = int hd l;		
				}
				
				srv.replydirect(ref Rmsg.Write(m.tag, len m.data));
			Qdata =>
				n := sys->write(conns[cn(path)].fds[1][0], m.data, len m.data);
				srv.replydirect(ref Rmsg.Write(m.tag, n));
			Qstderr =>
				n := sys->write(conns[cn(path)].fds[2][0], m.data, len m.data);
				srv.replydirect(ref Rmsg.Write(m.tag, n));	
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
				# need a way of looking up this connection number
				if(c != nil)
					q = qid(Qdata | (c.n << Shift));
			Qstderr =>
				if(c != nil)
					q = qid(Qstderr | (c.n << Shift));
			Qctl =>
				;
			Qstatus =>
				;
			Qwait =>
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
				"stderr" =>
					path = Qstderr | dp;
				"status" =>
					path = Qstatus | dp;
				"wait" =>
					path = Qwait | dp;
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
					if(string x == name)
						for(i := 0; i < nconns; i++)
							if(conns[i].n == x){
								path = (x << Shift) | Qdir;
								break;
							}
				}
			}
			n.reply <-= dirgen(path);
		Readdir =>
			d: array of int;
			case path & Mask {
			Qdir =>
				d = array[] of {Qctl, Qdata, Qstderr, Qstatus};
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
		perm = 8r666;
	Qstderr =>
		name = "stderr";
		perm = 8r666;
	Qstatus =>
		name = "status";
		perm = 8r666;
	Qwait =>
		name = "wait";
		perm = 8r666;	
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
	a: array of (int, int);		# (pid, tag)
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



spawner(c: chan of int, args: list of string, fd: array of array of ref Sys->FD)
{
	# why does this fail when I try to fork my fd namespace?
	# next I need to get the connection handing working correctly.
	# what about exception propogation?
#	c <-= sys->pctl(Sys->FORKFD,nil);
	c <-= sys->pctl(0,nil);
	sys->print("starting %s\n", hd args);			
	for(i := 0; i < 3; i++){
		if(sys->pipe(fd[i]) == -1)
			raise "fail: couldn't create pipe";
		sys->dup(fd[i][0].fd, i);
	}
	cmd := load Command hd args;
	if(cmd == nil)
		raise "fail: load command";
	cmd->init(nil, args);
	sys->sleep(300000000);
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
