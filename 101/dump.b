implement Btreetest;

include "sys.m";
	sys: Sys;
include "draw.m";
include "btree.m";
	btree: Btreem;
	Btree, Block, Entry, Datum : import btree;
Btreetest : module {
	init: fn(nil:ref Draw->Context, nil: list of string);
};

init(nil:ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	btree = load Btreem Btreem->PATH;
	
	btree->init();
	
	args = tl args;
	bt := Btree.open("index.bt", Sys->ORDWR);
	dump(bt, bt.getblock(bt.head), bt.H);
}

dump(b: ref Btree, h: ref Block, H: int)
{
	if(H == 0){
		for(i := 0; i < h.m; i++){
			sys->print("%s %s\n", string h.ents[i].key, string h.ents[i].val);
		
		}
	}
	
	if(H != 0)
		for(i := 0; i < h.m; i++)
			dump(b, b.getblock(g32(h.ents[i].val, 0)), H-1);
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
}
