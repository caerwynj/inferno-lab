implement Cryptfile;

include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
	keyring: Keyring;

stderr: ref Sys->FD;
fd: ref Sys->FD;
is: ref Keyring->IDEAstate;

BUFSIZE : con 512;  # make it the same for kfs
# e.g. 
# cryptfile /chan/crypt kfs.file '0123456789abcdef'
# mount -c {disk/kfs -r -s 2097152 -b 512 -P /chan/crypt} /n/kfs
Cryptfile: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr, "cryptfile chanfile diskfile key\n");
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	stderr = sys->fildes(2);

	if (argv != nil)
		argv = tl argv;
	if (len argv != 3)
		usage();
	path := hd argv;
	fd = sys->open(hd tl argv, Sys->ORDWR);
	key := array[16] of byte;
	for(i := 0; i < 16; i++)
		key[i] = byte (hd tl tl argv)[i];
	is = keyring->ideasetup(key, nil);

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
	sys->pctl(Sys->NEWPGRP, nil);
	for (;;) alt {
	(off, count, fid, rc) := <-fio.read =>
		if (rc == nil)
			continue;
		error: string = nil;
		ibuf := array[BUFSIZE] of byte;
		buf := array[count] of byte;
		b := buf[0:];
		addr := off % BUFSIZE;
		blk := off / BUFSIZE;
		tot := 0;
		while(count > 0) {
			n := count;
			if(n > (BUFSIZE - addr))
				n = BUFSIZE - addr;
			got := sys->pread(fd, ibuf, BUFSIZE,  big (blk * BUFSIZE));
			if(got == 0) {
				break;
			} else if(got != BUFSIZE) {
				error = "read: incomplete block";
				break;
			}
			keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Decrypt);
			b[0:] = ibuf[addr:addr + n];
			b = b[n:];
			count -= n;
			tot += n;
			blk++;
			addr = 0;
		}
		if(error != nil)
			rc <-= (nil, error);
		else
			rc <-= (buf[0:tot], nil);
	(off, data, fid, wc) := <-fio.write =>
		if (wc == nil)
			continue;
		error : string = nil;
		tot := 0;
		ibuf := array[BUFSIZE] of byte;
		b := data[0:];
		addr := off % BUFSIZE;
		blk := off / BUFSIZE;
		count := len data;
		while(count > 0) {
			n := count;
			if(n > (BUFSIZE - addr))
				n = BUFSIZE - addr;
			if(addr > 0  || count < BUFSIZE) {
				got := sys->pread(fd, ibuf, BUFSIZE,  big (blk * BUFSIZE));
				if(got == 0)
					;
				else if(got != BUFSIZE) {
					error = "write: incomplete block";
					break;
				}
				keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Decrypt);
				for(i:=0; i<n; i++)
					ibuf[addr+i] = b[i];
			} else {
				ibuf[0:] = b[0:n];
			}
			keyring->ideaecb(is, ibuf, BUFSIZE, keyring->Encrypt);
			sys->pwrite(fd, ibuf, BUFSIZE, big (blk * BUFSIZE));
			b = b[n:];
			count -= n;
			tot += n;
			blk++;
			addr = 0;
		}
		if(error != nil)
			wc <-= (0, error);
		else
			wc <-= (tot, nil);
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

