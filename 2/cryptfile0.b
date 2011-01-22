implement Cryptfile;

include "sys.m";
	sys: Sys;
include "draw.m";

stderr: ref Sys->FD;
fd: ref Sys->FD;

Cryptfile: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "cryptfile chanfile diskfile\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	if (argv != nil)
		argv = tl argv;
	if (len argv != 2)
		usage();
	path := hd argv;
	fd = sys->open(hd tl argv, Sys->ORDWR);

	(dir, f) := pathsplit(path);
	if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
		sys->fprint(stderr, "cryptfile: bind #s failed: %r\n");
		return;
	}
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		sys->fprint(stderr, "cryptfile: couldn't make %s: %r\n", path);
		return;
	}

	spawn cryptserver(fio);
}

cryptserver(fio: ref Sys->FileIO)
{
	for (;;) alt {
	(off, count, fid, rc) := <-fio.read =>
		if (rc == nil)
			continue;
		buf := array[count] of byte;
		n := sys->pread(fd, buf, count,  big off);
		rc <- = (buf[0:n], nil);
	(off, data, fid, wc) := <-fio.write =>
		if (wc == nil)
			continue;
		n := sys->pwrite(fd, data, len data, big off);
		wc <-= (n, nil);
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

