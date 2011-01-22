Btreem: module
{
	PATH: con "/dis/lib/btree.dis";

	Datum:	type array of byte;

	Btree: adt {
		create:	fn(file: string, perm: int): ref Btree;
		open:	fn(file: string, flags: int): ref Btree;
		
		fetch:	fn(b: self ref Btree, key: Datum): Datum;
		delete:	fn(b: self ref Btree, key: Datum): int;
		store:	fn(b: self ref Btree, key: Datum, val: Datum):int;
		firstkey:	fn(b: self ref Btree): Datum;
		nextkey:	fn(b: self ref Btree, key: Datum): Datum;

		flush:	fn(b: self ref Btree);
		close:	fn(b: self ref Btree);

		fd:	ref Sys->FD;
		cnt:	int;
		H:	int;
		head:	int;
		slop:	array of byte;
		dirty:	list of ref Block;
		cache:	ref Cache;
	};

	init:	fn();
	
	
	Entry: adt {
		size:	int;		# of the entry on disk
		zip:	int;		# prefix length for the key
		key:	Datum;
		val:	Datum;
	
		tobyte:	fn(e: self ref Entry): array of byte;
		frombyte:	fn(b: array of byte): ref Entry;
		new:		fn(key: Datum, val: Datum): ref Entry;
	};
	
	Block: adt {
		size:	int;
		seq:	int;
		m:	int;
		esize:	int;
		ents:	array of ref Entry;
		
		tstamp:	int;	# for the cache
	
		tobyte:	fn(b: self ref Block): array of byte;
		frombyte:	fn(buf: array of byte): ref Block;
		addentry:	fn(h: self ref Block, e: ref Entry, j, zip: int): int;
		delentry:	fn(h: self ref Block, j: int): int;
	};

	Cache: adt{
		cache: array of list of ref Block;

		create: fn(): ref Cache;
		lookup: fn(c: self ref Cache, id: int): ref Block;
		store: fn(c: self ref Cache, b: ref Block);
	};
};
