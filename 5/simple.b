implement Ffs;

include "ffs.m";

init(nil: list of string)
{
	config("hello world\n");
}

config(s: string): string
{
	configstr = s;
	return nil;
}

read(n: int): array of byte
{
	a := array[n] of {* => byte 'a'};
	return a;
}
