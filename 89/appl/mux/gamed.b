implement gamed;

include "sys.m";
include "string.m";
include "draw.m";

sys: Sys;
str: String;
Connection, FD, FileIO: import Sys;
Context: import Draw;

devsysname: con "/dev/sysname";
tagsize: con 5;

channo: int = 0;
rsalt:	int;

stderr: ref FD;

sysname: string;
server: string;
iamserver: int;
err: array of byte;
errlen: int;
beof: array of byte;

gamerchan: chan of (string, ref FD, string);
tagchan: chan of (string, ref FD, ref FD, ref FD);

gamed: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	str = load String String->PATH;
	if (str == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", String->PATH);
		return;
	}

	if (len argv != 2) {
		sys->fprint(stderr, "usage: gamed server\n");
		return;
	}

	err = array of byte "error";
	errlen = len err;
	beof = array[1] of byte;
	beof[0] = byte 255;
	sysname = getsysname();
	if (sysname == nil)
		return;
	server = hd tl argv;
	iamserver = servercmp();
	sys->fprint(stderr, "gamed: %s -> %s\n", sysname, server);
	sys->fprint(stderr, "gamed: iamserver %d\n", iamserver);

	gamerchan = chan of (string, ref FD, string);
	spawn marshall();

	tagchan = chan of (string, ref FD, ref FD, ref FD);
	spawn rondezvous();

	(ok, c) := sys->announce("tcp!*!gamed");
	if (ok < 0) {
		sys->fprint(stderr, "announce failed: %r\n");
		return;
	}

	while (serve(c) >= 0)
		;
}

getsysname() : string
{
	f := sys->open(devsysname, sys->OREAD);
	if (f == nil) {
		sys->fprint(stderr, "open %s failed: %r\n", devsysname);
		return nil;
	}
	buff := array[64] of byte;
	n := sys->read(f, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read %s failed: %r\n", devsysname);
		return nil;
	}
	return string buff[0:n];
}

servercmp() : int
{
	if (server == sysname)
		return 1;

	vl := len server;
	yl := len sysname;
	return vl < yl && str->prefix(server, sysname) && sysname[vl:vl+1] == ".";
}

serve(k: Connection) : int
{
	(ok, nc) := sys->listen(k);
	if (ok < 0) {
		sys->fprint(stderr, "listen failed: %r\n");
		return -1;
	}

	df := nc.dir + "/data";
	nc.dfd = sys->open(df, sys->ORDWR);
	if (nc.dfd == nil) {
		sys->fprint(stderr, "open %s failed: %r\n", df);
		return -1;
	}

	buff := array[64] of byte;
	n := sys->read(nc.dfd, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read %s failed: %r\n", df);
		return -1;
	}
	if (n == 0)
		return 0;
	m := string buff[0:n];
	sys->fprint(stderr, "[%s]\n", m);
	(c, l) := sys->tokenize(m, " \t\n");
	if (c > 0) case hd l {
	"join" =>
		if (c == 2) {
			if (iamserver)
				spawn join(nc.dfd, hd tl l, sysname);
			else
				spawn proxy(nc.dfd, hd tl l);
			return 0;
		}
		else if (c == 3) {
			if (iamserver) {
				spawn join(nc.dfd, hd tl l, hd tl tl l);
				return 0;
			}
			else
				sys->fprint(stderr, "unexpected server join\n");
		}
		else
			sys->fprint(stderr, "join nargs\n");
	"local" =>
		if (c == 4) {
			spawn local(nc.dfd, hd tl l, hd tl tl l, hd tl tl tl l);
			return 0;
		}
		else
			sys->fprint(stderr, "local nargs\n");
	"remote" =>
		if (c == 2) {
			spawn remote(nc.dfd, hd tl l);
			return 0;
		}
		else
			sys->fprint(stderr, "remote nargs\n");
	* =>
		sys->fprint(stderr, "bad command %s\n", hd l);
	}
	sys->write(nc.dfd, err, errlen);
	return 0;
}

join(f: ref FD, game, host: string)
{
	gamerchan <-= (game, f, host);
}

proxy(f: ref FD, game: string)
{
	a := "tcp!" + server + "!gamed";
	(ok, c) := sys->dial(a, nil);
	if (ok < 0) {
		sys->fprint(stderr, "dial %s failed: %r\n", a);
		return;
	}
	s := "join " + game + " " + sysname;
	b := array of byte s;
	if (sys->write(c.dfd, b, len b) < 0) {
		sys->fprint(stderr, "write error to %s\n", server);
		return;
	}
	buff := array[64] of byte;
	n := sys->read(c.dfd, buff, len buff);
	if (n < 0) {
		sys->fprint(stderr, "read error from %s\n", server);
		return;
	}
	sys->fprint(stderr, "[proxy %s]\n", string buff[0:n]);
	if (sys->write(f, buff, n) < 0)
		sys->fprint(stderr, "write error in proxy\n");
}

local(f: ref FD, tag, host, player: string)
{
	opponent: string;

	if (player == "0")
		opponent = "1";
	else
		opponent = "0";
	a := "tcp!" + host + "!gamed";
	(ok, c) := sys->dial(a, nil);
	if (ok < 0) {
		sys->fprint(stderr, "dial %s failed: %r\n", a);
		return;
	}
	s := "remote " + tag + "." + opponent;
	b := array of byte s;
	if (sys->write(c.dfd, b, len b) < 0) {
		sys->fprint(stderr, "write error to %s\n", host);
		return;
	}
	tagchan <-= (tag + "." + player, f, c.dfd, nil);
}

remote(f: ref FD, tag: string)
{
	tagchan <-= (tag, nil, nil, f);
}

marshall()
{
	gamerlist, l, n: list of (string, ref FD, string);

outer:	for (;;) {
		(game, f, host) := <- gamerchan;
		l = gamerlist;
		n = nil;

		while (l != nil) {
			h := hd l;
			l = tl l;
			(tg, tf, th) := h;

			if (tg == game) {
				spawn newgame(game, f, host, tf, th);
				while (l != nil) {
					n = hd l :: n;
					l = tl l;
				}
				gamerlist = n;
				continue outer;
			}

			n = h :: n;
		}

		gamerlist = (game, f, host) :: n;
	}
}

salt()
{
	rsalt = sys->millisec();
}

rand(n: int): int
{
	rsalt = rsalt * 1103515245 + 12345;
	if (n == 0)
		return 0;
	return ((rsalt & 16r7FFFFFFF) >> 10) % n;
}

tag() : string
{
	s := "";

	for (i := 0; i < tagsize; i++)
		s = s + sys->sprint("%.2x", rand(256));

	return s;
}

newgame(game: string, f0: ref FD, h0: string, f1: ref FD, h1: string)
{
	t := tag();
	sys->fprint(stderr, "newgame: %s [%s] %s v %s\n", game, t, h0, h1);
	spawn sendtag(t, f0, h1, 0);
	spawn sendtag(t, f1, h0, 1);
}

sendtag(tag: string, f: ref FD, opp: string, ord: int)
{
	s := tag + " " + opp + " " + string ord;
	sys->fprint(stderr, "<%s>\n", s);
	b := array of byte s;
	sys->write(f, b, len b);
}

rondezvous()
{
	taglist, l, n: list of (string, ref FD, ref FD, ref FD);

outer:	for (;;) {
		(mt, ml, mrc, mr) := <- tagchan;
		l = taglist;
		n = nil;

		while (l != nil) {
			h := hd l;
			l = tl l;
			(nt, nl, nrc, nr) := h;

			if (nt == mt) {
				if (nr == nil)
					spawn joinplayers(nl, nrc, mr);
				else
					spawn joinplayers(ml, mrc, nr);
				while (l != nil) {
					n = hd l :: n;
					l = tl l;
				}
				taglist = n;
				continue outer;
			}

			n = h :: n;
		}

		taglist = (mt, ml, mrc, mr) :: n;
	}
}

joinplayers(l, rc, r: ref FD)
{
	if (l == nil || rc == nil || r == nil) {
		sys->fprint(stderr, "bad rondezvous\n");
		return;
	}

	f := "gamed." + string channo++;
	wf := "/chan/" + f;
	sys->bind("#s", "/chan", Sys->MBEFORE);
	sv := sys->file2chan("/chan", f);
	if (sv == nil) {
		sys->fprint(stderr, "file2chan %s failed: %r\n", wf);
		return;
	}

	b := array of byte wf;
	if (sys->write(l, b, len b) < 0) {
		sys->fprint(stderr, "local write failed: %r\n");
		return;
	}

	spawn copier(l, rc, "local", "remote call");
	spawn chanserver(r, sv, "remote", wf);
}

copier(r, w: ref FD, rn, wn: string)
{
	b := array[1] of byte;

	for (;;) {
		n := sys->read(r, b, 1);
		if (n < 0) {
			sys->fprint(stderr, "read %s error: %r\n", rn);
			return;
		}
		if (n == 0) {
			sys->fprint(stderr, "%s eof\n", rn);
			return;
		}
#		sys->fprint(stderr, "{%s %d}\n", rn, int b[0]);
		if (b[0] == beof[0])
			return;
		if (sys->write(w, b, 1) < 0) {
			sys->fprint(stderr, "write %s error: %r\n", wn);
			return;
		}
	}
}

chanserver(r: ref FD, w: ref FileIO, rn, wn: string)
{
	b := array[1] of byte;

	for (;;) {
		n := sys->read(r, b, 1);
		if (n < 0) {
			sys->fprint(stderr, "read %s error: %r\n", rn);
			break;
		}
		if (n == 0) {
			sys->fprint(stderr, "%s eof\n", rn);
			break;
		}
#		sys->fprint(stderr, "{%s %d}\n", rn, int b[0]);
		if (b[0] == beof[0]) {
			sys->fprint(stderr, "%s end game\n", rn);
			break;
		}
		(offset, count, fid, rc) := <- w.read;
		rc <-= (b, nil);
	}

#	if (sys->remove(wn) < 0)
#		sys->fprint(stderr, "remove %s failed: %r\n", wn);
}
