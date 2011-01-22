implement Btreekeys;

include "sys.m";
	sys: Sys;

include "draw.m";

include "btree.m";
	btreem: Btreem;
	Btree: import btreem;

Btreekeys : module {
	init: fn(nil:ref Draw->Context, args: list of string);
};

init(nil:ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	btreem = load Btreem Btreem->PATH;
	
	btreem->init();
	
	args = tl args;
	index := "index.bt";
	if(len args > 0){
		index = hd args;
	}
	bt := Btree.open(index, Sys->ORDWR);
	
	for(key := bt.firstkey(); key != nil; key = bt.nextkey(key))
		sys->print("%s\n", string key);
}
