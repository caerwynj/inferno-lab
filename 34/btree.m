Btreem: module
{
	PATH: con "/dis/folkfs/btree.dis";

	Datum:	type array of byte;
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
		
		tstamp:		int;	# for the cache

		tobyte:	fn(b: self ref Block): array of byte;
		frombyte:	fn(buf: array of byte): ref Block;
		addentry:	fn(h: self ref Block, e: ref Entry, j, zip: int): int;
		delentry:	fn(h: self ref Block, j: int): int;
	};

	Btree: adt {
		cache:	ref Cachem->Cache;
		fd:	ref Sys->FD;
		cnt:	int;
		H:	array of int;
		head:	array of int;
		inversion:	int;
		lockfile:	string;		# served by lockfs
		tran: int;
		slop: array of byte;
		dirty: list of ref Block;

		search:	fn(b: self ref Btree, key: Datum): (Datum, Datum);
		insert:	fn(b: self ref Btree, key: Datum, val: Datum):int;
		delete:	fn(b: self ref Btree, key: Datum): int;
		flush:	fn(b: self ref Btree);
		getblock:	fn(b: self ref Btree, id: int): ref Block;
		putblock:	fn(b: self ref Btree, blk: ref Block);
		close:	fn(b: self ref Btree);
		rlock:	fn(b: self ref Btree): ref Sys->FD;
		wlock:	fn(b: self ref Btree): ref Sys->FD;
	};

	Path: adt {
		index:	int;
		id:	int;
		height:	int;
		blk: ref Block;
	};

	Cursor: adt {
		b:	ref Btree;
		path:	array of Path;
		top:	int;
		flags:	int;
		last:	ref Entry;		# last seen by tt toggle
		ungetbuf:	ref Entry;	# unget buffer of one
		tran: int;			# transaction count
		start: ref Entry;		# starting position
		pos: ref Entry;		# position for relocation

		reader: fn(b: ref Btree, key: Datum): (chan of ref Entry, int);
		locate: fn(b: ref Btree, key: Datum): ref Cursor;
		next: fn(c: self ref Cursor): ref Entry;
		get: fn(c: self ref Cursor): ref Entry;
		rget: fn(c: self ref Cursor): ref Entry;
		unget: fn(c: self ref Cursor);
		push: fn(c: self ref Cursor, p: Path);
		pop: fn(c: self ref Cursor): Path;
		reloc:	fn(c: self ref Cursor);
	};

	Sequence: adt {
		b: ref Btree;
		offset: int;
		next: fn(s: self ref Sequence): int;
		current: fn(s: self ref Sequence): int;
		init: fn(b: ref Btree, id: int): ref Sequence;
	};

	open:	fn(f: string, flag: int, lockfile: string): ref Btree;
	init:	fn();
};
