implement Cachem;

include "cache.m";
include "sys.m";
include "btree.m";
include "daytime.m";

daytime: Daytime;
#Nhash: con 64;
Nhash: con 8;
Mcache: con 4;

# A lockless cache with last in wins for readers
# a writer always wins
#readers only trivially modify the block by updating the timestamp
# writers hold the btree lock so are the only ones accessing it anyway.

Cache.create(): ref Cache
{
	if(daytime == nil)
		daytime = load Daytime Daytime->PATH;
	c := ref Cache;
	c.cache = array[Nhash] of list of ref Btreem->Block;
	return c;
}

Cache.lookup(c: self ref Cache, id: int): ref Btreem->Block
{
	for(bl := c.cache[id%Nhash]; bl != nil; bl = tl bl){
		b := hd bl;
		if(b.seq == id){
			b.tstamp = daytime->now();
			return b;
		}
	}
	return nil;
}

Cache.store(c: self ref Cache, b: ref Btreem->Block)
{
	if(c.lookup(b.seq) != nil)
		return;
	b.tstamp = daytime->now();
	h := b.seq%Nhash;
	ol := c.cache[h];
	while(len ol >= Mcache){
		evict := -1;
		t := Sys->Maxint;
		for(l := ol; l != nil; l = tl l){
			if((hd l).tstamp < t){
				t = (hd l).tstamp;
				evict = (hd l).seq;
			}
		}
		l = nil;
		for(;ol != nil; ol = tl ol)
			if((hd ol).seq != evict)
				l = hd ol :: l;
		ol = l;
	}

	# last in wins!
	c.cache[h] = b :: ol;
}
