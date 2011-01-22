implement Srv;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";

Srv: module {
	init:fn(ctxt:ref Draw->Context, args:list of string);
};

init(ctxt:ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;

	path: string;
	args = tl args;
	if(len args != 2)
		fail("usage", "usage: srv cmd file");
	addr := hd args;
	args = tl args;
	path = hd args;
	(dir, f) := pathsplit(path);
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
			fail("error", "no #s");
		}
		fio = sys->file2chan(dir, f);
		if (fio == nil)
			fail("error", "cannot make chan");
	}
	fd := connect(ctxt, addr);
	sync := chan of int;
	spawn srv(sync, fio, fd);
	<-sync;
}

srv(sync: chan of int, fio: ref Sys->FileIO, fd: ref Sys->FD)
{
	sync <-= sys->pctl(0, nil);
	for (;;) {
		fid, offset, count: int;
		rc: Sys->Rread;
		wc: Sys->Rwrite;
		d: array of byte;
		alt {
		(offset, count, fid, rc) = <-fio.read =>
			if (rc != nil) {
				spawn putrdata(offset, fid, count, rc, fd);
			} else
				continue;		# we get a close on both read and write...
		(offset, d, fid, wc) = <-fio.write =>
			if (wc != nil) {
				n  := sys->write(fd, d, len d);
				wreply(wc, n, nil);
			}
		}
	}
}

connect(ctxt: ref Draw->Context, dest: string): ref Sys->FD
{
	if(dest != nil && dest[0] == '{' && dest[len dest - 1] == '}'){
		return popen(ctxt, dest :: nil);
	}
	(n, nil) := sys->tokenize(dest, "!");
	if(n == 1){
		fd := sys->open(dest, Sys->ORDWR);
		if(fd != nil){
			return fd;
		}
		if(dest[0] == '/')
			fail("open failed", sys->sprint("can't open %s: %r", dest));
	}
	svc := "styx";
	dest = netmkaddr(dest, "net", svc);
	(ok, c) := sys->dial(dest, nil);
	if(ok < 0)
			fail("dial failed",  sys->sprint("can't dial %s: %r", dest));
	return c.dfd;
}

popen(ctxt: ref Draw->Context, argv: list of string): ref Sys->FD
{
	sh := load Sh Sh->PATH;
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(sh, ctxt, argv, fds[0], sync);
	<-sync;
	return fds[1];
}

runcmd(sh: Sh, ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh->run(ctxt, argv);
}

putrdata(nil, nil, count: int, rc: chan of (array of byte, string), fd: ref Sys->FD)
{
	buf := array[count] of byte;
	n := sys->read(fd, buf, count);
	rreply(rc, buf[0:n], nil);
}

wreply(wc: chan of (int, string), count: int, err: string)
{
	alt {
	wc <-= (count, err) => ;
	* => ;
	}
}

rreply(rc: chan of (array of byte, string), d: array of byte, err: string)
{
	alt {
	rc <-= (d, err) => ;
	* => ;
	}
}

pathsplit(p: string): (string, string)
{
	for (i := len p - 1; i >= 0; i--)
		if (p[i] != '/')
			break;
	if (i < 0)
		return (p, nil);
	p = p[0:i+1];
	for (i = len p - 1; i >=0; i--)
		if (p[i] == '/')
			break;
	if (i < 0)
		return (".", p);
	return (p[0:i+1], p[i+1:]);
}

fail(status, msg: string)
{
	sys->fprint(sys->fildes(2), "srv: %s\n", msg);
	raise "fail:"+status;
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, nil) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
