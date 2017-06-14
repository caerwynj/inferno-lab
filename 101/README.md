#   NAME
lab 101 - limbo B+ tree

#   NOTES
This lab is an implementation of a B+ tree. It is code from a much older lab that was overly complicated and buggy. I pulled the B+ tree code out, tried to fix the bugs and clean it up. The interface is roughly the same as dbm(2). Here is a synopsis.

	include "btree.m";
	btreem := load Btreem Btreem->PATH;
	Datum, Btree: import Btreem;
	
	Btree: adt {
	 create: fn(file: string, perm: int): ref Btree;
	 open: fn(file: string, flags: int): ref Btree;
	 
	 fetch: fn(b: self ref Btree, key: Datum): Datum;
	 delete: fn(b: self ref Btree, key: Datum): int;
	 store: fn(b: self ref Btree, key: Datum, val: Datum):int;
	
	 firstkey: fn(b: self ref Btree): Datum;
	 nextkey: fn(b: self ref Btree, key: Datum): Datum;
	
	 flush: fn(b: self ref Btree);
	 close: fn(b: self ref Btree);
	};
	
	init: fn();

Like Dbm the keys and values are stored as arrays of bytes, and being a B+tree the values are stored only in the leaf nodes. The maximum key and val size is 255 each. The block size is 8192, so the maximum leaf node size is 515 making the minimum branching factor 15. The maximum number of records in an internal nodes assuming an int as key is 630.

The delete is not fully implemented; it doesn't merge nodes.

Here is some example code listing the full contents of a btree.

	sys := load Sys Sys->PATH;
	btreem := load Btreem Btreem->PATH;
	Datum, Btree: import btreem;
	
	btreem->init();
	bt := Btree.open("index.bt", Sys->ORDWR);
	for(key := bt.firstkey(); key != nil; key = bt.nextkey(key)){
	 v := bt.fetch(key);
	 sys->print("%s %s\n", string key, string v);
	}

Here is a rough comparison of btree vs. dbm. This simple test is more of a sanity check that the btree doesn't do anything horribly wrong in its implementation (which it did originally, by making a syscall to get the daytime for every block it tried to get).

	% awk '{print $1, NR}' < /lib/words | tr -d 'cr' > t1
	
	% >index.bt
	% >dbm.pag
	% >dbm.dir
	
	% time sh -c 'btree/store < t1' 
	0l 4.172r 4.172t
	
	% time sh -c 'dbm/store dbm < t1'
	0l 35.25r 35.25t
	
	% ls -l dbm.* index.bt
	--rw-rw---- M 6 xcs0998 XCS0998    8192 Jun 04 12:38 dbm.dir
	--rw-rw---- M 6 xcs0998 XCS0998 1048576 Jun 04 12:38 dbm.pag
	--rw-rw---- M 6 xcs0998 XCS0998 770048 Jun 04 12:36 index.bt
	
	% time sh -c 'btree/list > /dev/null'
	0l 5.187r 5.187t
	
	% time sh -c 'dbm/list dbm > /dev/null'
	0l 9.438r 9.438t
