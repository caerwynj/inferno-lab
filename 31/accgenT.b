implement Accgen;
include "sys.m";
include "draw.m";
include "keyring.m";

Accgen: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys := load Sys Sys->PATH;
	keyring := load Keyring Keyring->PATH;
	IPint: import keyring;
	Num: type ref IPint;

	spawn accgen(c := chan of (Num, chan of chan of (Num, chan of Num)));
	c <-= (Num.inttoip(99), reply := chan of chan of (Num, chan of Num));
	ac := <-reply;

	for(argv = tl argv; argv != nil; argv = tl argv){
		ac <-= (Num.strtoip(hd argv, 10), acreply := chan of Num);
		sys->print("%s\n", (<-acreply).iptostr(10));
	}
}

accgen[T](c: chan of (T, chan of chan of (T, chan of T)))
	for{
	T =>
		add: fn(a: self T, b: T): T;
	}
{
	for(;;){
		(n, reply) := <-c;
		spawn acc(n, ac := chan of (T, chan of T));
		reply <-= ac;
	}
}

acc[T](n: T, c: chan of (T, chan of T))
	for{
	T =>
		add: fn(a: self T, b: T): T;
	}
{
	for(;;){
		(i, reply) := <-c;
		reply <-= n.add(i);
	}
}
