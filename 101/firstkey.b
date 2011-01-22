implement Btreetest;

include "sys.m";
include "draw.m";
include "btree.m";

Btreetest : module {
	init: fn(nil:ref Draw->Context, nil: list of string);
};

init(nil:ref Draw->Context, args: list of string)
{
	sys := load Sys Sys->PATH;
	btree := load Btreem "/usr/xcs0998/limbo/btree/btree.dis";
	Btree : import btree;
	args = tl args;
	
	btree->init();
	index := "index.bt";
	if(len args > 0){
		index = hd args;
		args = tl args;
	}
	bt := Btree.open(index, Sys->ORDWR);
	key := bt.firstkey();
	sys->print("%s\n", string key);
}
