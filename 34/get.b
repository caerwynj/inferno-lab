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
include "util.m";
	util: Util;
	p32: import util;
include "query.m";

stderr: ref Sys->FD;
stdin: ref Sys->FD;

Getpost: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};


init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	util = load Util Util->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	arg->init(args);	
	qstr := "";
	while((c := arg->opt()) != 0) {
		case c {
		'q' =>
			qstr = arg->earg();
		* =>
			sys->fprint(stderr, "%s: bad option %c\n", arg->progname(), c);
			usage(arg->progname());
		}
	}
	if(qstr == nil)
		exit;
	args = arg->argv();
	n := len args;
	wait := chan of int;
	for( ; args != nil; args = tl args)
		spawn runq(hd args, qstr, wait);
	for( ; n > 0; n--)
		<-wait;
}

runq(index: string, q: string, c: chan of int)
{
	sys->pctl(Sys->NEWPGRP, nil);
	lex := load Lexis Lexis->PATH;
	query := load Query Query->PATH;
	lex->init(index);
	query->init(lex);
	(pid, U) := query->query(q);
	while((u := <-U) != nil){
		for( ; u != nil; u = tl u){
			sys->print("%s ", hd u);
		}
		sys->print("\n");
	}
	query->kill(pid);
	lex->close();
	c <-= 0;
}


usage(s: string)
{
	sys->fprint(stderr, "usage: %s [-q query] index ...\n", s);
	exit;
}
