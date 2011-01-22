implement Btreem;

include "sys.m";
	sys: Sys;
	fprint, seek, read, write, print: import sys;
include "cache.m";
	cachem: Cachem;
	Cache: import cachem;
include "btree.m";
include "util.m";
	util: Util;
	prefixlen, acomp, p32, g32: import util;

BLOCK:	con (1024*8);
HEADR:	con 36;
ENTFIXLEN:	con 5;   # size[2] zip[1] n[1] key[n] n[1] val[n]
EINIT:	con 1;
EGROW:	con 2;
CACHE:	con 32;

last: ref Entry;
stdout, stderr: ref Sys->FD;
debug := 0;

fatalerror(s:string)
{
	sys->fprint(sys->fildes(2), "%s%r\n", s);
	exit;
}

init()
{
	sys = load Sys Sys->PATH;
	cachem = load Cachem Cachem->PATH;
	if(cachem == nil)
		fatalerror("cachem");
	util = load Util Util->PATH;
	if(util == nil)
		fatalerror("util");
}

bloffset(n: int): big
{
	return big (n * BLOCK);
}

open(f: string, flag: int, lock: string): ref Btree
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);
	if(cachem == nil)
		cachem = load Cachem Cachem->PATH;

	buf := array[BLOCK] of {* => byte 0};
	b := ref Btree;
	b.lockfile = lock;
	b.cache = Cache.create();
	(nd, nil) := sys->stat(f);
	if(nd == -1)
		b.fd = sys->create(f, flag, 8r666);
	else
		b.fd = sys->open(f, flag);
	b.fd = sys->open(f, flag);
	if(b.fd == nil)
		return nil;
	b.H = array[4] of {0, 0, 0, 0};
	b.head = array[4] of {0, 0, 0, 0};
	b.tran = 0;
	b.cnt = 0;
	b.inversion = 2;
	b.slop = buf[HEADR:];
	if (sys->pread(b.fd, buf, BLOCK, big 0) < BLOCK)
		return b;
	i := 0;
	b.cnt =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
	for(j := 0; j < 4; j++) {
		b.H[j] =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
	}
	for(j = 0; j < 4; j++) {
		b.head[j] =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
	}
	b.slop = buf[i:];
	return b;
}

Btree.close(b: self ref Btree)
{
	b.flush();			# should this be locked
}

Btree.flush(b: self ref Btree)
{
	buf := array[BLOCK] of byte;

	if(debug)
		sys->print("cnt %d; H %d, %d, %d; head %d, %d, %d\n", 
		b.cnt, b.H[1], b.H[2], b.H[3], b.head[1], b.head[2], b.head[3]);

	if(b.dirty == nil)
		return;
	i := 0;
	buf[i++] = byte b.cnt;
	buf[i++] = byte (b.cnt>>8);
	buf[i++] = byte (b.cnt>>16);
	buf[i++] = byte (b.cnt>>24);
	for(j := 0; j < 4; j++) {
		buf[i++] = byte b.H[j];
		buf[i++] = byte (b.H[j]>>8);
		buf[i++] = byte (b.H[j]>>16);
		buf[i++] = byte (b.H[j]>>24);
	}
	for(j = 0; j < 4; j++) {
		buf[i++] = byte b.head[j];
		buf[i++] = byte (b.head[j]>>8);
		buf[i++] = byte (b.head[j]>>16);
		buf[i++] = byte (b.head[j]>>24);
	}
	p := buf[i:];
	p[0:] = b.slop;
	if(sys->pwrite(b.fd, buf, BLOCK, big 0) != BLOCK)
		raise "header";

	for( ; b.dirty != nil; b.dirty = tl b.dirty){
		blk := hd b.dirty;
		p = blk.tobyte();
		if(sys->pwrite(b.fd, p, len p, bloffset(blk.seq)) != len p)
			raise "putblock";
	}
}

stringof(a: array of byte, l: int, u: int): Datum
{
	if (u > len a){
		sys->fprint(stderr, "stringof: string size bigger than array\n");
		u = len a;
	} else if (u < l)
		u = l;
	return a[l:u];
}

Block.tobyte(b: self ref Block): array of byte
{
	buf := array[BLOCK] of byte;
	n := 0;
	ts := 2;
	buf[0] = byte b.size;
	buf[1] = byte (b.size >> 8);
	p := buf[2:];
	for(i := 0; i < b.m; i++) {
		ts += b.ents[i].size;
		if(ts > BLOCK)
			raise "tobyte";
		n = convE2M(b.ents[i], p);
		p = p[n:];
	}
	if (ts != b.size)
		sys->fprint(stderr, "tobyte: blk size mismatch %d vs. %d\n", ts, b.size);
	return buf;
}

Block.frombyte(buf: array of byte): ref Block
{
	b := ref Block(2, 0, 0, 0, nil, 0);
	sz := ((int buf[0]) | (int buf[1] << 8));
	p: array of byte;
	m: int;
	e : ref Entry;
	nn := 0;
	for(i := 2; i < sz; i+=m) {
		p = buf[i:];
		e = Entry.frombyte(p);
		m = e.size;
		b.addentry(e, nn, UNZIP);
		nn++;
	}
	if(sz != i)
		sys->fprint(stderr, "frombyte: blk size mismatch %d vs. %d\n", sz, i);
	return b;
}

convE2M(e: ref Entry, buf: array of byte): int
{
	i := 0;
	if(debug)
		sys->print("size %d zip %d key %d val %d\n", e.size, e.zip, len e.key, len e.val);
	buf[i++] = byte e.size;
	buf[i++] = byte (e.size>>8);
	buf[i++] = byte e.zip;
	buf[i++] = byte (len e.key - e.zip);
	p := buf[i:];
	p[0:] = e.key[e.zip:];
	i += (len e.key - e.zip);
	buf[i++] = byte (len e.val);
	p = buf[i:];
	p[0:] = e.val[0:];
	i += len e.val;
	return  i;
}

Btree.getblock(b: self ref Btree, id: int): ref Block
{
	n: ref Block;
	if(id > 100000)
		raise "bad id";
	if((n = b.cache.lookup(id)) != nil)
		return n;
	for(l := b.dirty; l != nil; l = tl l){
		if((hd l).seq == id){
			b.cache.store(hd l);
			return hd l;
		}
	}
	buf := array[BLOCK] of byte;
	i := sys->pread(b.fd, buf, BLOCK, bloffset(id));
	if (i <= 0)
		n = ref Block(2, 0, 0, 0, nil, 0);
	else
		n = Block.frombyte(buf);
	if(n != nil){
		n.seq = id;
		b.cache.store(n);
	}
	return n;
}

Btree.putblock(b: self ref Btree, blk: ref Block)
{
	if(debug)
		sys->print("blk %d; size %d, m %d, esize %d\n", 
			blk.seq, blk.size, blk.m, blk.esize);
	if(blk.seq > 100000)
		raise "bad seq";
	if(len b.dirty >= 10)
		b.flush();
	for(l := b.dirty; l != nil; l = tl l)
		if((hd l).seq == blk.seq)
			return;
	b.dirty = blk :: b.dirty;
#	p := blk.tobyte();
#	if(sys->pwrite(b.fd, p, len p, bloffset(blk.seq)) != len p)
#		raise "putblock";
}

Btree.insert(b: self ref Btree, key: Datum, val: Datum): int
{
	n := 0;
	lock := b.wlock();
{
	if(key != nil)
		key = (array[len key] of byte)[0:] = key;
	if(val != nil)
		val = (array[len val] of byte)[0:] = val;
	insertInv(b, key, val);
#	b.flush();
}exception e{
	"getblock" =>
		sys->fprint(stderr, "%s: error reading block %r\n", e);
		n = -1;
	"putblock" =>
		sys->fprint(stderr, "%s: error writing block %r\n", e);
		n = -1;
	"header" =>
		sys->fprint(stderr, "%s: error writing header %r\n", e);
		n = -1;
	"tobyte" =>
		sys->fprint(stderr, "%s: error block size exceeded\n", e);
		n = -1;
	"bad id" =>
		sys->fprint(stderr, "%s: error bad block id\n", e);
		n = -1;
}
	lock = nil;
	return n;
}

insertInv(b:  ref Btree, key: Datum, val: Datum)
{
	u0, u1, e: ref Entry;
	t, h: ref Block;
# TODO truncate key and val so Entry does not exceed maxsize
	if(len key > 255 || len val > 255){
		sys->fprint(sys->fildes(2), "key/val too long\n");
		return;
	}
	inv := b.inversion;
	if(b.head[inv] == 0) {
		b.cnt++;
		b.head[inv] = b.cnt;
	}
	h = b.getblock(b.head[inv]);
	e = Entry.new(key, val);
	b.tran++;
	u1 = insertR(b, h, e, b.H[inv]);
	if(u1 == nil)
		return;
	t = b.getblock(++(b.cnt));
	buf := array[4] of byte;
	p32(buf, 0, h.seq);
	u0 = Entry.new(h.ents[0].key, buf);
	t.addentry(u0, 0, DOZIP);
	t.addentry(u1, 1, DOZIP);
	b.putblock(t);
	b.head[inv] = t.seq;
	b.H[inv]++;
}

insertR(b: ref Btree, h: ref Block, e: ref Entry, H: int): ref Entry
{
	j, n: int;
	x: ref Entry;

	x = e;
	if(H == 0){
		(j, n) = bsearch(h, e, 0, h.m-1);
		if(j < h.m && n == 0)		# no duplicate keys
			return nil;
	}
	if(H != 0) {
		(j, n) = bsearch(h, e, 1, h.m-1);
		j--;
		x = insertR(b, b.getblock(g32(h.ents[j++].val, 0)), e, H-1);
		if(x == nil)
			return nil;
	}
	h.addentry(x, j, DOZIP);
	if(h.size < BLOCK){
		b.putblock(h);
		return nil;
	}else
		return split(b, h);
}

Btree.search(b: self ref Btree, key: Datum): (Datum, Datum)
{
	ret : (Datum, Datum);
	lock := b.rlock();
{
	ret = (nil, nil);
	inv := b.inversion;
	if(b.head[inv] == 0)
		raise "end";
	h := b.getblock(b.head[inv]);
	e := Entry.new(key, nil);
	ee := searchR(b, h, e, b.H[inv]);
	if(ee == nil)
		ret = (nil, nil);
	else
		ret = (ee.key, ee.val);
}exception e{
	"getblock" =>
		sys->fprint(stderr, "%s: error reading block %r\n", e);
	"tobyte" =>
		sys->fprint(stderr, "%s: error block size exceeded\n", e);
	"bad id" =>
		sys->fprint(stderr, "%s: error bad block id\n", e);
	"end" =>
		;
}
	lock = nil;
	return ret;
}

searchR(b: ref Btree, h: ref Block, e: ref Entry, H: int): ref Entry
{
	u: ref Entry;
	u = nil;
	if(H == 0){
		(j, n) := bsearch(h, e, 0, h.m-1);
		if(j == h.m)
			return nil;
		if(n == 0 || n == -1)
			u = h.ents[j];
	}
	if(H != 0){
		(j, nil) := bsearch(h, e, 1, h.m-1);
		j--;
		u = searchR(b, b.getblock(g32(h.ents[j].val, 0)), e, H-1);
	}
	return u;
}

Btree.delete(b: self ref Btree, key: Datum): int
{
	n := 0;
	lock := b.wlock();
{
	deleteInv(b, key);
#	b.flush();
}exception e{
	"getblock" =>
		sys->fprint(stderr, "%s: error reading block %r\n", e);
		n = -1;
	"putblock" =>
		sys->fprint(stderr, "error writing block %r\n");
		n = -1;
	"header" =>
		sys->fprint(stderr, "error writing header %r\n");
		n = -1;
	"tobyte" =>
		sys->fprint(stderr, "error block size exceeded\n");
		n = -1;
	"bad id" =>
		sys->fprint(stderr, "error bad block id\n");
		n = -1;
}
	lock = nil;
	return n;
}

deleteInv(b:  ref Btree, key: Datum)
{
	u1, e: ref Entry;
	h: ref Block;
	inv := b.inversion;
	h = b.getblock(b.head[inv]);
	e = Entry.new(key, nil);
	u1 = deleteR(b, h, e, b.H[inv]);
	if(u1 == nil)
		return;
# assuming it is not possible to split a block through deletion of an entry.
	b.tran++;
}

#TODO untested
deleteR(b: ref Btree, h: ref Block, e: ref Entry, H: int): ref Entry
{
	j: int;
	u: ref Entry;

	if(H == 0){
		for(j = 0; j < h.m; j++)
			if(acomp(e.key, h.ents[j].key) == 0){
				h.delentry(j);
			}
		if(j == 0){
			buf:=array[4] of byte;
			p32(buf, 0, h.seq);
			return Entry.new(h.ents[0].key, buf); 
		}else
			return nil;
	}
	if(H != 0) {
		for(j = 0; j< h.m; j++) {
			if((j + 1 == h.m) || less(e, h.ents[j+1])) {
				u = deleteR(b, b.getblock(g32(h.ents[j++].val, 0)), e, H-1);
				if(u == nil)
					return nil;
				h.delentry(j);
				h.addentry(u, j, DOZIP);  # is DOZIP the right thing here?
				if(h.size < BLOCK){ 
					return nil;
				}else			# is this possible?
					return split(b, h);
			}
		}
	}
	return nil;
}

Block.delentry(h: self ref Block, j: int): int
{
	e, l: ref Entry;
	if(j > h.m)
		return -1;
	h.size -= h.ents[j].size;
	h.m--;
	for(i := j; i < h.m; i++)
		h.ents[i] = h.ents[i+1];
	 # adjust the prefixlen 
	e = h.ents[j];
	if(j > 0){
		l = h.ents[j - 1];
		zip := e.zip;
		e.zip = prefixlen(e.key, l.key);
		e.size += (zip - e.zip);
		h.size += (zip - e.zip);
	}else{
		e.size += e.zip;
		h.size += e.zip;
		e.zip = 0;
	}
	return h.m;
}

DOZIP: con 1;
MVZIP: con 2;
UNZIP: con 3;

Block.addentry(h: self ref Block, e: ref Entry, j: int, zip: int): int
{
	evp: array of ref Entry;

	if(h.ents == nil) {
		h.ents = array[EINIT] of ref Entry;
		h.esize = EINIT;
		h.m = 0;
	} else if(h.m >= h.esize) {
		evp = array[h.esize * EGROW] of ref Entry;
		h.esize *= EGROW;
		evp[0:] = h.ents[0:];
		h.ents = evp;
	}
	if(j > h.m)	
		return -1;
	for(i := h.m++; i > j; i--)
		h.ents[i] = h.ents[i-1];
	h.ents[j] = e;
	h.size += e.size;
	case zip{
	DOZIP =>
		dozip(h, j);
	MVZIP =>
		mvzip(h, j);
	UNZIP =>
		unzip(h, j);
	}
	return h.m;
}

split(b: ref Btree, h: ref Block): ref Entry
{
	j, k, ts: int;
	link: ref Entry;
	t: ref Block;

	ts = 0;
	t = b.getblock(++b.cnt);
	for(j = 0; j < h.m; j++) {
		ts += h.ents[j].size;
		if(ts >= BLOCK/2)
			break;
	}
	ts = 0;
	for(k = 0; k + j < h.m; k++) {
		ts += h.ents[k+j].size;
		t.addentry(h.ents[k+j], k, MVZIP);
	}
	h.m -= k;
	h.size -= ts;
	buf := array[4] of byte;
	p32(buf, 0, t.seq);
	link = Entry.new(t.ents[0].key, buf);
	b.putblock(h);	
	b.putblock(t);
	return link;
}

# this is called when inserting a new entry
# not when splitting a block or unpacking a block
dozip(h: ref Block, j: int)
{
	zip: int;
	e, l, n: ref Entry;
	e = h.ents[j];
	if(j > 0)
		l = h.ents[j - 1];
	else
		l = nil;
	if((j + 1) < h.m)
		n = h.ents[j + 1];
	else
		n = nil;
	zip = h.ents[j].zip;
	if(j == 0){
		e.zip = 0;
		return;
	}
	if(l != nil){
		e.zip = prefixlen(l.key, e.key);
		e.size -= e.zip;
		h.size -= e.zip;
	}
	if(n != nil){
		zip = n.zip;
		n.zip = prefixlen(e.key, n.key);
		n.size += (zip - n.zip);
		h.size += (zip - n.zip);
	}
}

# this is called when we split a block
mvzip(h: ref Block, j: int)
{
	e := h.ents[j];
	if(j == 0 && e.zip != 0){
		e.size += e.zip;
		h.size += e.zip;
		e.zip = 0;
	}
}

# this is called when unpacking a block
unzip(h: ref Block, j: int)
{
	e, l: ref Entry;

	e = h.ents[j];
	if(j == 0)
		return;
	else if(j > 0)
		l = h.ents[j - 1];
	if(e.zip != 0){
		suffix := e.key;
		e.key = (array[len e.key + e.zip] of byte)[0:] = l.key[0:e.zip];
		p := e.key[e.zip:];
		p[0:] = suffix;
	}
}

Cursor.reader(b: ref Btree, key: Datum): (chan of ref Entry, int)
{
	c := ref Cursor;
	c.b = b;
	c.path = array[5] of Path;
	c.top = 0;
	c.tran = -1;
	c.start = ref Entry(0, 0, key, key);
	c.pos = nil;
	Z := chan of ref Entry;
	pidc := chan of int;
	spawn readerp(c, Z, pidc);
	pid := <-pidc;
	return (Z, pid);
}

# lock is freed with process is killed
readerp(c: ref Cursor, U: chan of ref Entry, pidc: chan of int)
{
	lock := c.b.rlock();
{
	pidc <-= sys->pctl(0, nil);
	c.reloc();
	for(;;) 
		U <-= c.get();
}exception ec{
	"bad id" =>
		sys->fprint(stderr, "%s: error bad block id\n", ec);
	"getblock" =>
		sys->fprint(stderr, "error reading block %r\n");
	"end" =>
		;
}
	lock = nil;
}

Cursor.locate(b: ref Btree, key: Datum): ref Cursor
{
	c := ref Cursor;
	c.b = b;
	c.path = array[5] of Path;
	c.top = 0;
	c.tran = -1;
	c.start = ref Entry(0, 0, key, key);
	c.pos = nil;

	return c;
}

# NOTE we removed the c.pos functionality. if we reloc after a change
# in the btree we won't end up in the same position
# but we expect to replace this with processes for the cursor which hold the lock
Cursor.reloc(c: self ref Cursor)
{
	p: Path;
	h: ref Block;
	e: ref Entry;

	c.last = nil;
	c.ungetbuf = nil;
	c.tran = c.b.tran;
	if(c.pos == nil)
		e = c.start;
	else
		e = c.pos;
	while(c.top > 0)
		c.pop();
	c.push(Path(0, c.b.head[c.b.inversion], c.b.H[c.b.inversion], nil));
	for(;;){
		p = c.pop();
		if(p.blk == nil)
			h = p.blk = c.b.getblock(p.id);
		if(p.height == 0){
			(p.index, nil) = bsearch(h, e, 0, h.m-1);
			p.index--;
			c.push(p);
			break;
		}else{
			(p.index, nil) = bsearch(h, e, 1, h.m-1);
			p.index--;
			c.push(p);
			c.push(Path(0, g32(h.ents[p.index].val, 0), p.height - 1, nil));
		}
	}	
}

bsearch(b: ref Block, e: ref Entry, bot, top: int): (int, int)
{
	mid, n: int;
	if(top < 0)
		return (0,-1);
	while(top>=bot){
		mid = (top+bot)/2;
		n = acomp(e.key, b.ents[mid].key);
		case(n){
		-2 or -1 or 0 =>
			top = mid-1;
		1 or 2 =>
			bot = mid+1;
		}
	}
	for(i:=bot;i<b.m;i++){
		n = acomp(e.key, b.ents[i].key);
		case(n){
		-2 or -1 or 0 =>
			return (i, n);
		1 or 2 =>
			continue;
		}
	}
	return (i, n);
}

Cursor.next(c: self ref Cursor): ref Entry
{
	e: ref Entry;

	lock := c.b.rlock();
{
	if(c.tran != c.b.tran)
		c.reloc();
	e = c.get();
	c.pos = e;
}exception ec{
	"bad id" =>
		sys->fprint(stderr, "%s: error bad block id\n", ec);
	"getblock" =>
		sys->fprint(stderr, "error reading block %r\n");
}
	lock = nil;
	return e;
}

Cursor.get(c: self ref Cursor): ref Entry
{
	for(;;){
		if(c.top == 0)
			return nil;
		p := c.pop();
		if(p.blk == nil && (p.blk = c.b.getblock(p.id)) == nil)
			return nil;
		if(p.index + 1 >= p.blk.m)
			continue;
		else
			p.index++;
		c.push(p);
		if(p.height == 0){
			return p.blk.ents[p.index];
		}else{
			c.push(Path(-1, g32(p.blk.ents[p.index].val, 0), p.height - 1, nil));
		}
	}
}

# go backwards
Cursor.rget(c: self ref Cursor): ref Entry
{
	for(;;){
		if(c.top == 0)
			return nil;
		p := c.pop();
		if(p.blk == nil && (p.blk = c.b.getblock(p.id)) == nil)
			return nil;
		else if(p.index == -2)
			p.index = p.blk.m;
		if(p.index - 1 < 0)
			continue;
		else
			p.index--;
		c.push(p);
		if(p.height == 0){
			return p.blk.ents[p.index];
		}else{
			c.push(Path(-2, g32(p.blk.ents[p.index].val, 0), p.height - 1, nil));
		}
	}
}

Cursor.unget(c: self ref Cursor)
{
	if(c.top == 0)
		return;
	p := c.pop();
	c.last = c.ungetbuf;
	p.index--;
	c.push(p);
}

Cursor.push(c: self ref Cursor, p: Path)
{
	if(c.top >= len c.path)
		c.path = (array[len c.path + 5] of Path)[0:] = c.path;
	c.path[c.top++] = p;
}

Cursor.pop(c: self ref Cursor): Path
{
	return c.path[--c.top];
}


Entry.new(key: Datum, val: Datum): ref Entry
{
	e: ref Entry;
	size := ENTFIXLEN + len key + len val;
	e = ref Entry(size, 0, key, val);	
	return e;
}

less(s: ref Entry, t: ref Entry): int
{
	i := acomp(s.key, t.key);
	if(i <= 0)
		return 1;
	else
		return 0;
}

Entry.tobyte(e: self ref Entry): array of byte
{
	akey, aval, p: array of byte;
	akey = e.key;
	aval = e.val;
	i := 0;
	s := ENTFIXLEN + len akey + len aval;
	buf := array[s] of byte;
	buf[i++] = byte s;
	buf[i++] = byte (s>>8);
	buf[i++] = byte e.zip;
	buf[i++] = byte (len akey);
	p = buf[i:];
	p[0:] = akey[0:];
	i += len akey;
	buf[i++] = byte (len aval);
	p = buf[i:];
	p[0:] = aval[0:];
	i += len aval;
	return  buf;
}

Entry.frombyte(b: array of byte): ref Entry
{
	e := ref Entry;
	ts := ENTFIXLEN;
	i := 0;
	e.size =	(int b[i++]<<0)|(int b[i++]<<8);
	e.zip =	int b[i++];
	ns := 	int b[i++];
	ts += ns;
	e.key = stringof(b, i, i + ns);
	i += ns;
	ns =		int b[i++];
	ts += ns;
	e.val = stringof(b, i, i + ns);
	if(e.size != ts)
		sys->fprint(stderr, "warning esize, ts mismatch %d %d\n", e.size, ts);
	return e;
}

Sequence.next(s: self ref Sequence): int
{
	n := 0;
	lock := s.b.wlock();
{
	n = g32(s.b.slop, s.offset);
	n++;
	p32(s.b.slop, s.offset, n);
#	s.b.flush();  #we expect sequences are used for inserts so insert will flush
}exception e{
	"header" =>
		sys->fprint(stderr, "%s: error writing header %r\n", e);
		n = -1;
}
	lock = nil;
	return n;
}

Sequence.current(s: self ref Sequence): int
{
	n := 0;
	lock := s.b.rlock();
	n = g32(s.b.slop, s.offset);
	lock = nil;
	return n;
}

Sequence.init(b: ref Btree, id: int): ref Sequence
{
	if(id * 4 > len b.slop)
		return nil;
	else
		return ref Sequence(b, id * 4);
}

Btree.rlock(b: self ref Btree): ref Sys->FD
{

	if(0)
		return sys->open(b.lockfile, Sys->OREAD);
	return nil;
}


Btree.wlock(b: self ref Btree): ref Sys->FD
{
	if(0)
		return sys->open(b.lockfile, Sys->ORDWR);
	return nil;
}
