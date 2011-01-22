implement Dump;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "hash.m";
	hash: Hash;
	HashTable: import hash;
include "string.m";
	str: String;
include "arg.m";
	arg: Arg;
include "cache.m";
include "btree.m";
	btreem: Btreem;
	Btree: import btreem;
include "names.m";
	names: Names;
include "workdir.m";
	workdir: Workdir;
include "lexis.m";
	lex: Lexis;
	Position, Fact, Rule, Category, Relation, Attribute, Object: import lex;

bt: ref Btree;
stderr: ref Sys->FD;
stdin: ref Sys->FD;

Dump: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

nthread:int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	hash = load Hash Hash->PATH;
	str = load String String->PATH;
	lex = load Lexis Lexis->PATH;
	btreem = load Btreem Btreem->PATH;
	names = load Names Names->PATH;
	workdir = load Workdir Workdir->PATH;
	arg = load Arg Arg->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	arg->init(args);	
	index:="index.bt";
	nthread = 1;
	while((c := arg->opt()) != 0) {
		case c {
		'i' =>
			index = arg->earg();
		'p' =>
			nthread = int arg->earg();
		* =>
			sys->fprint(stderr, "%s: bad option %c\n", arg->progname(), c);
			usage(arg->progname());
		}
	}
	args = arg->argv();
	cc := chan of int;
	spawn run(index, args, cc);
	pid := <-cc;
	<-cc;
	kill(pid);
}

kill(pid: int)
{
	path := sys->sprint("#p/%d/ctl", pid);
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

run(index: string, nil: list of string, c: chan of int)
{
	c <-= sys->pctl(Sys->NEWPGRP, nil);
	lex->init(index);
	buf := array[4] of { * => byte 0};
	p := Position.mk(buf);
	while((fact := p.next()) != nil)
		fact.print();
	lex->close();
	c <-=1;
	c <-=1;
}

usage(name: string)
{
	sys->fprint(sys->fildes(2), "usage: %s index.bt\n",  name);
	exit;
}
