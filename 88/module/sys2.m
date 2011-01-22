
SELF:	con	"$self";		# Language support for loading my instance

Sys: module
{
	PATH:	con	"$Sys";

	# Details on exception
	Exception: adt
	{
		name:	string;
		mod:	string;
		pc:	int;
	};

	# Parameters to exception handlers
	HANDLER,
	EXCEPTION,
	ACTIVE,
	RAISE,
	EXIT,
	ONCE:	con	iota;

	# Unique file identifier for file objects
	Qid: adt
	{
		path:	int;
		vers:	int;
	};

	# Return from stat and directory read
	Dir: adt
	{
		name:	string;
		uid:	string;
		gid:	string;
		qid:	Qid;
		mode:	int;
		atime:	int;
		mtime:	int;
		length:	int;
		dtype:	int;
		dev:	int;
	};

	# File descriptor
	#
	FD: adt
	{
		fd:	int;
	};

	# Network connection returned by dial
	#
	Connection: adt
	{
		dfd:	ref FD;
		cfd:	ref FD;
		dir:	string;
	};

	# File IO structures returned from file2chan
	# read:  (offset, bytes, fid, chan)
	# write: (offset, data, fid, chan)
	#
	Rread:	type chan of (array of byte, string);
	Rwrite:	type chan of (int, string);
	FileIO: adt
	{
		read:	chan of (int, int, int, Rread);
		write:	chan of (int, array of byte, int, Rwrite);
	};

	# Maximum read which will be completed atomically;
	# also the optimum block size
	#
	ATOMICIO:	con 8192;

	NAMELEN:	con 28;

	SEEKSTART:	con 0;
	SEEKRELA:	con 1;
	SEEKEND:	con 2;

	ERRLEN:		con 64;
	WAITLEN:	con ERRLEN;

	OREAD:		con 0;
	OWRITE:		con 1;
	ORDWR:		con 2;
	OTRUNC:		con 16;
	ORCLOSE:	con 64;
	CHDIR:		con int 16r80000000;

	MREPL:		con 0;
	MBEFORE:	con 1;
	MAFTER:		con 2;
	MCREATE:	con 4;

	NEWFD:		con (1<<0);
	FORKFD:		con (1<<1);
	NEWNS:		con (1<<2);
	FORKNS:		con (1<<3);
	NEWPGRP:	con (1<<4);
	NODEVS:		con (1<<5);

	EXPWAIT:	con 0;
	EXPASYNC:	con 1;
	EXPEXCL:	con 2;

	UTFmax:		con 3;
	UTFerror:	con 16r80;

	announce:	fn(addr: string): (int, Connection);
	aprint:		fn(s: string, *): array of byte;
	bind:		fn(s, on: string, flags: int): int;
	byte2char:	fn(buf: array of byte, n: int): (int, int, int);
	char2byte:	fn(c: int, buf: array of byte, n: int): int;
	chdir:		fn(path: string): int;
	create:		fn(s: string, mode, perm: int): ref FD;
	dial:		fn(addr, local: string): (int, Connection);
	dirread:	fn(fd: ref FD, dir: array of Dir): int;
	dup:		fn(old, new: int): int;
	export:		fn(c: ref FD, flag: int): int;
	fildes:		fn(fd: int): ref FD;
	file2chan:	fn(dir, file: string): ref FileIO;
	fprint:		fn(fd: ref FD, s: string, *): int;
	fstat:		fn(fd: ref FD): (int, Dir);
	fwstat:		fn(fd: ref FD, d: Dir): int;
	listen:		fn(c: Connection): (int, Connection);
	millisec:	fn(): int;
	mount:		fn(fd: ref FD, on: string, flags: int, spec: string): int;
	open:		fn(s: string, mode: int): ref FD;
	pctl:		fn(flags: int, movefd: list of int): int;
	pipe:		fn(fds: array of ref FD): int;
	print:		fn(s: string, *): int;
	raise:		fn(s: string);
	rescue:		fn(s: string, e: ref Exception): int;
	rescued:	fn(flag: int, s: string): int;
	read:		fn(fd: ref FD, buf: array of byte, n: int): int;
	remove:		fn(s: string): int;
	seek:		fn(fd: ref FD, off, start: int): int;
	sleep:		fn(period: int): int;
	sprint:		fn(s: string, *): string;
	stat:		fn(s: string): (int, Dir);
	stream:		fn(src, dst: ref FD, bufsiz: int): int;
	tokenize:	fn(s, delim: string): (int, list of string);
	unmount:	fn(s1: string, s2: string): int;
	unrescue:	fn();
	utfbytes:	fn(buf: array of byte, n: int): int;
	write:		fn(fd: ref FD, buf: array of byte, n: int): int;
	wstat:		fn(s: string, d: Dir): int;
};
