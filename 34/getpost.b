implement Getpost;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "arg.m";
	arg: Arg;
include "cache.m";
include "btree.m";
include "lexis.m";
	lex: Lexis;
	Fact, Position: import lex;
include "util.m";
	util: Util;
	p32: import util;
include "query.m";
	query: Query;

stderr: ref Sys->FD;
stdin: ref Sys->FD;

Getpost: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};


init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	lex = load Lexis Lexis->PATH;
	query = load Query Query->PATH;
	arg = load Arg Arg->PATH;
	util = load Util Util->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	arg->init(args);	
	index:="index.bt";
	while((c := arg->opt()) != 0) {
		case c {
		'i' =>
			index = arg->earg();
		* =>
			sys->fprint(stderr, "%s: bad option %c\n", arg->progname(), c);
			usage(arg->progname());
		}
	}
	args = arg->argv();
	lex->init(index);
	query->init(lex);
	(pid, U) := query->query(hd args);
	while((u := <-U) != nil){
		for( ; u != nil; u = tl u){
			sys->print("%s ", hd u);
		}
		sys->print("\n");
	}
	query->kill(pid);
	lex->close();
}

usage(s: string)
{
	sys->fprint(stderr, "usage: %s [-i index] file\n", s);
	exit;
}
