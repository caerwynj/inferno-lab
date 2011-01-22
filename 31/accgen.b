implement Accgen;
include "sys.m";
	sys: Sys;
include "draw.m";

Accgen: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	spawn accgen(c := chan of (int, chan of chan of (int, chan of int)));
	c <-= (99, reply := chan of chan of (int, chan of int));
	ac := <-reply;

	for(argv = tl argv; argv != nil; argv = tl argv){
		ac <-= (int hd argv, acreply := chan of int);
		sys->print("%d\n", <-acreply);
	}
}

accgen(c: chan of (int, chan of chan of (int, chan of int)))
{
	for(;;){
		(n, reply) := <-c;
		spawn acc(n, ac := chan of (int, chan of int));
		reply <-= ac;
	}
}

acc(n: int, c: chan of (int, chan of int))
{
	for(;;){
		(i, reply) := <-c;
		reply <-= n+i;
	}
}
