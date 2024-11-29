# Libraries
* 101 limbo B+ tree
* 73 MIDI library
* 20 libmux
* 18 mux; generic multiplexer
* Inferno ML numpy like library 

### lab 101 - limbo B+ tree
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



### lab 18 - mux
Much of my recent reading has led me back to various
implementations of a multiplexer. This is an important and powerful
abstraction and I want to understand it better. I know very little about
it now.
I'd like to implement
one in limbo, for example to multiplex the link between sam and samterm
as suggested in the 
[protium](http://cm.bell-labs.com/who/cyoung/papers/hotos-final.pdf)
paper. Hence my interest in sam in the earlier lab.

Here is a some of the things I've been reading recently about multiplexers.
See if you notice a pattern.
J. Hickey's Master thesis at MIT implements
[mux](http://www.pdos.lcs.mit.edu/papers/plan9:jmhickey-meng.pdf)
for plan9 which puts a 9p multiplexer into user space and provides
asynchonous IO for user threads.

Search 9fans for
[multiplexing](http://groups.google.com/groups?hl=en&lr=&ie=ISO-8859-1&q=multiplexing&meta=group%3Dcomp.os.plan9) 
where there is some interesting discussion on the use of multiplexers in plan9.

For example, an 
[idea](http://groups.google.com/groups?hl=en&lr=&ie=UTF-8&frame=right&th=cacc1588716799cb&seekm=499f328d8dc6462edbadb7e4894feaf8%40vitanuova.com#s)
by rog and russ's
[response](http://groups.google.com/groups?hl=en&lr=&ie=UTF-8&selm=C9C19233.4D3B50B5%40mail.gmail.com)
And futher proposals by russ:
[proposal](http://groups.google.com/groups?q=g:thl264888595d&dq=&hl=en&lr=&ie=UTF-8&selm=70b1be7bf1a870538ecd7c40d8b83810%40plan9.bell-labs.com)
for mux, 
[local](http://groups.google.com/groups?q=russ+9p+auth&hl=en&lr=&ie=UTF-8&group=comp.os.plan9&selm=C6BFF847.5A05ABE1%40mail.gmail.com&rnum=6)
9p multiplexing and
[remote](http://groups.google.com/groups?q=russ+9p+auth&hl=en&lr=&ie=UTF-8&group=comp.os.plan9&selm=C6B52136.4C686BD7%40mail.gmail.com&rnum=2)
9p multiplexing.

See also an implementation of a generic rpc multiplexer, libmux, in
[plan9port](http://swtch.com/plan9port)

The various window systems by Rob Pike, mux, 8½, and rio are multiplexers
for their environment, the screen, mouse and keyboard.

The spree game engine is a multiplexer at the application level
for the object hierarchy managed by the server.

And in inferno `/emu/port/devmnt.c`
is the multiplexer for 9p.

In the original 
[exokernel](http://www.pdos.lcs.mit.edu/papers/hotos-jeremiad.ps)
paper the authors argued the principal
function of an operating system is to multiplex access to hardware,
and should do nothing else. Multiplexers are vital to providing
9p service and in protium the authors argue they are a vital
piece of infrastructure for distributed applications. 

### lab 20 - libmux in limbo
To learn about mux in detail I tried to implement libmux in
limbo. It actually resembles the mux from libventi more than libmux.
They are pretty similar.

I was going to do a detailed description of the mux in devmnt
but it turns out this has already been done 
[here](http://plan9.escet.urjc.es/usr/nemo/9.txt.gz)
by nemo.

When I get this working it can be applied
to the venti lib for session rpc, to build a libfs
for direct client 9p interaction, bypassing devmnt,
and for application protocol muxing, say for sam.

This is a partial implementation. I didn't complete
.IR send ,
.IR  recv ,
.I gettag 
and 
.I settag
functions, so
this has not been tested. 

I'm just posting it here now so I don't lose track of it.
I'll come back to it later, maybe writing more for the Venti library
or libfs. This is more an excercise to understand the workings of libmux
and venti's session rpc.

  http://caerwyn.com/lab/20/mux.b mux.b
  http://caerwyn.com/lab/20/mux.m mux.m
