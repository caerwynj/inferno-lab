implement Btreem;

include "sys.m";
	sys: Sys;
	fprint, seek, read, write, print, fildes, pwrite, pread: import sys;

include "btree.m";

BIT8SZ:	con 1;
BIT16SZ:	con 2;
BIT32SZ:	con 4;
BIT64SZ:	con 8;
BLOCK:	con (1024*8);
HEADR:	con 36;
ENTFIXLEN:	con 5;   # size[2] zip[1] n[1] key[n] n[1] val[n]
EINIT:	con 1;
EGROW:	con 2;
CACHE:	con 32;

stdout, stderr: ref Sys->FD;
debug := 0;

init()
{
	sys = load Sys Sys->PATH;
	stdout = fildes(1);
	stderr = fildes(2);
}

fatalerror(s:string)
{
	fprint(fildes(2), "%s%r\n", s);
	exit;
}

bloffset(n: int): big
{
	return big (n * BLOCK);
}

Btree.create(file: string, mode: int): ref Btree
{
	fd := sys->create(file, Sys->ORDWR, mode);
	if(fd == nil)
		return nil;
	return alloc(fd);
}

Btree.open(f: string, mode: int): ref Btree
{
	fd := sys->open(f, mode);
	if(fd == nil)
		return nil;
	return alloc(fd);	
}

alloc(fd: ref Sys->FD): ref Btree
{
	buf := array[BLOCK] of {* => byte 0};
	b := ref Btree;
	b.cache = Cache.create();
	b.fd = fd;
	b.H = 0;
	b.head = 0;
	b.cnt = 0;
	b.slop = buf[HEADR:];
	if (sys->pread(b.fd, buf, BLOCK, big 0) < BLOCK)
		return b;
	i := 0;
	b.cnt =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
	b.H =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
	b.head =	(int buf[i++]<<0)|
			(int buf[i++]<<8)|
			(int buf[i++]<<16)|
			(int buf[i++]<<24);
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
		sys->print("cnt %d; H %d; head %d\n", 
		b.cnt, b.H, b.head);

	if(b.dirty == nil)
		return;
	i := 0;
	buf[i++] = byte b.cnt;
	buf[i++] = byte (b.cnt>>8);
	buf[i++] = byte (b.cnt>>16);
	buf[i++] = byte (b.cnt>>24);
	buf[i++] = byte b.H;
	buf[i++] = byte (b.H>>8);
	buf[i++] = byte (b.H>>16);
	buf[i++] = byte (b.H>>24);
	buf[i++] = byte b.head;
	buf[i++] = byte (b.head>>8);
	buf[i++] = byte (b.head>>16);
	buf[i++] = byte (b.head>>24);
	p := buf[i:];
	p[0:] = b.slop;
	if(sys->pwrite(b.fd, buf, BLOCK, big 0) != BLOCK)
		raise "btree: write header error"+sys->sprint("%r");

	for( ; b.dirty != nil; b.dirty = tl b.dirty){
		blk := hd b.dirty;
		p = blk.tobyte();
		if(sys->pwrite(b.fd, p, len p, bloffset(blk.seq)) != len p)
			raise "btree: write header error"+sys->sprint("%r");
	}
}

stringof(a: array of byte, l: int, u: int): Datum
{
	if (u > len a){
		fprint(stderr, "stringof: string size bigger than array\n");
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
			raise "btree: tobyte";
		n = convE2M(b.ents[i], p);
		p = p[n:];
	}
	if (ts != b.size)
		fprint(stderr, "tobyte: blk size mismatch %d vs. %d\n", ts, b.size);
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

getblock(b: ref Btree, id: int): ref Block
{
	n: ref Block;
	if(id > 100000)
		raise "btree: bad id";
	if((n = b.cache.lookup(id)) != nil)
		return n;
	for(l := b.dirty; l != nil; l = tl l){
		if((hd l).seq == id){
			b.cache.store(hd l);
			return hd l;
		}
	}
	if(debug)
		sys->fprint(sys->fildes(2), "cache miss %d\n", id);
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

putblock(b: ref Btree, blk: ref Block)
{
	if(debug)
		sys->print("blk %d; size %d, m %d, esize %d\n", 
			blk.seq, blk.size, blk.m, blk.esize);
	if(blk.seq > 100000)
		raise "btree: bad seq";
	if(len b.dirty >= 10)
		b.flush();
	for(l := b.dirty; l != nil; l = tl l)
		if((hd l).seq == blk.seq)
			return;
	b.dirty = blk :: b.dirty;
#	p := blk.tobyte();
#	if(sys->pwrite(b.fd, p, len p, bloffset(blk.seq)) != len p)
#		raise "btree: putblock";
}

Btree.store(b: self ref Btree, key: Datum, val: Datum): int
{
	n := 0;
	if(key != nil)
		key = (array[len key] of byte)[0:] = key;
	if(val != nil)
		val = (array[len val] of byte)[0:] = val;
	#  truncate key and val so Entry does not exceed maxsize
	if(len key > 255 || len val > 255){
		sys->fprint(sys->fildes(2), "key/val too long\n");
		return -1;
	}
	
	u0, u1, e: ref Entry;
	t, h: ref Block;
	if(b.head == 0) {
		b.cnt++;
		b.head = b.cnt;
	}
	h = getblock(b, b.head);
	e = Entry.new(key, val);
	u1 = insertR(b, h, e, b.H);
	if(u1 == nil)
		return n;
	t = getblock(b, ++(b.cnt));
	buf := array[4] of byte;
	p32(buf, 0, h.seq);
	u0 = Entry.new(h.ents[0].key, buf);
	t.addentry(u0, 0, DOZIP);
	t.addentry(u1, 1, DOZIP);
	putblock(b, t);
	b.head = t.seq;
	b.H++;
#	b.flush();
	return n;
}


Btree.firstkey(b: self ref Btree): Datum
{
	h := getblock(b, b.head);
	height := b.H;
	while (height > 0){
		h = getblock(b, g32(h.ents[0].val, 0));
		height--;
	}
	return h.ents[0].key;
}

Btree.nextkey(b: self ref Btree, key: Datum): Datum
{
	ret : Datum;
	ret = nil;
	if(b.head == 0)
		return ret;
	h := getblock(b, b.head);
	e := Entry.new(key, nil);
	ee := searchRnext(b, h, e, b.H);
	if(ee == nil)
		ret = nil;
	else
		ret = ee.key;
	return ret;
}

searchRnext(b: ref Btree, h: ref Block, e: ref Entry, H: int): ref Entry
{
	u: ref Entry;
	u = nil;
	if(H == 0){
		(j, n) := bsearch(h, e, 0, h.m-1);
		if(j == h.m)
			return nil;
		if(n == 0 && j < h.m-1)
			u = h.ents[j+1];
	}
	if(H != 0){
		(j, n) := bsearch(h, e, 1, h.m-1);
		if(n != 0 && j != 0)
			j--;
		u = searchRnext(b, getblock(b, g32(h.ents[j].val, 0)), e, H-1);
		if(u == nil  && j < h.m-1)
			u = h.ents[j+1];
	}
	return u;
}

insertR(b: ref Btree, h: ref Block, e: ref Entry, H: int): ref Entry
{
	j, n: int;
	x: ref Entry;

	x = e;
	if(H == 0){
		(j, n) = bsearch(h, e, 0, h.m-1);
		# if(j < h.m && n == 0)		# no duplicate keys
		#	return nil;
	}
	if(H != 0) {
		(j, n) = bsearch(h, e, 1, h.m-1);
		j--;
		x = insertR(b, getblock(b, g32(h.ents[j++].val, 0)), e, H-1);
		if(x == nil)
			return nil;
	}
	if(H == 0 && j < h.m && n == 0){  # exact match to exising key
		h.size = h.size - len h.ents[j].val + len x.val;
		h.ents[j].size = h.ents[j].size - len h.ents[j].val + len x.val;
		h.ents[j].val = x.val;
	}else
		h.addentry(x, j, DOZIP);
	if(h.size < BLOCK){
		putblock(b, h);
		return nil;
	}else
		return split(b, h);
}

Btree.fetch(b: self ref Btree, key: Datum): Datum
{
	ret : Datum;
	ret = nil;
	if(b.head == 0)
		return ret;
	h := getblock(b, b.head);
	e := Entry.new(key, nil);
	ee := searchR(b, h, e, b.H);
	if(ee == nil)
		ret = nil;
	else
		ret = ee.val;
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
		(j, n) := bsearch(h, e, 0, h.m-1);
		if(n != 0 && j != 0)
			j--;
		u = searchR(b, getblock(b, g32(h.ents[j].val, 0)), e, H-1);
	}
	return u;
}

Btree.delete(b: self ref Btree, key: Datum): int
{
	n := 0;
	u1, e: ref Entry;
	h: ref Block;
	h = getblock(b, b.head);
	e = Entry.new(key, nil);
	u1 = deleteR(b, h, e, b.H);
	if(u1 == nil)
		return -1;
# assuming it is not possible to split a block through deletion of an entry.
#	b.flush();
	return n;
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
				u = deleteR(b, getblock(b, g32(h.ents[j++].val, 0)), e, H-1);
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
	t = getblock(b, ++b.cnt);
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
	putblock(b, h);	
	putblock(b, t);
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

bsearch(b: ref Block, e: ref Entry, bot, top: int): (int, int)
{
	mid, n: int;
	if(top < 0)
		return (0,-1);
	while(top>=bot){
		mid = (top+bot)/2;
		n = acomp(e.key, b.ents[mid].key);
		case(n){
		0 =>
			return (mid, n);
		-2 or -1 =>
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


# Cache

Nhash: con 64;   # for cache
#Nhash: con 8;
Mcache: con 4;  # for cache
cacheseq := 0;

# A lockless cache with last in wins for readers
# a writer always wins
#readers only trivially modify the block by updating the timestamp
# writers hold the btree lock so are the only ones accessing it anyway.

Cache.create(): ref Cache
{
	c := ref Cache;
	c.cache = array[Nhash] of list of ref Block;
	return c;
}

Cache.lookup(c: self ref Cache, id: int): ref Block
{
	for(bl := c.cache[id%Nhash]; bl != nil; bl = tl bl){
		b := hd bl;
		if(b.seq == id){
			b.tstamp = cacheseq++;
			return b;
		}
	}
	return nil;
}

Cache.store(c: self ref Cache, b: ref Block)
{
	if(c.lookup(b.seq) != nil)
		return;
	b.tstamp = cacheseq++;
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


# Util

min(a,b,c: int): int
{
	t: int;
	if(a<b)
		t = a;
	else
		t = b;
	if(t < c)
		return t;
	else
		return c;
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+BIT32SZ;
}

p64(a: array of byte, o: int, b: big): int
{
	i := int b;
	a[o] = byte i;
	a[o+1] = byte (i>>8);
	a[o+2] = byte (i>>16);
	a[o+3] = byte (i>>24);
	i = int (b>>32);
	a[o+4] = byte i;
	a[o+5] = byte (i>>8);
	a[o+6] = byte (i>>16);
	a[o+7] = byte (i>>24);
	return o+BIT64SZ;
}

g32(f: array of byte, i: int): int
{
	return (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
}

g64(f: array of byte, i: int): big
{
	b0 := (((((int f[i+3] << 8) | int f[i+2]) << 8) | int f[i+1]) << 8) | int f[i];
	b1 := (((((int f[i+7] << 8) | int f[i+6]) << 8) | int f[i+5]) << 8) | int f[i+4];
	return (big b1 << 32) | (big b0 & 16rFFFFFFFF);
}

gvint(f: array of byte, i: int): int
{
	b := int f[i++];
	n := b & 16r7F;
	for(shift := 7; (b & 16r80) != 0; shift += 7) {
		b = int f[i++];
		n |= (b & 16r7F) << shift;
	}
	return n;
}

gvbig(f: array of byte, i: int): big
{
	b := big f[i++];
	n := big b & big 16r7F;
	for(shift := 7; (b & big 16r80) != big 0; shift += 7) {
		b = big f[i++];
		n |= (b & big 16r7F) << shift;
	}
	return n;
}

pvint(a: array of byte, o: int, v: int): int
{
	while((v & ~16r7F) != 0){
		a[o++] = byte ((v & 16r7F) | 16r80);
#		v = v >> 7;	#TODO this needs to be an unsigned shift
		v = (v >> 7 & 16r01ffffff);
	}
	a[o++] = byte v;
	return o;
}


# acomp returns:
#		-2 if s strictly precedes t
#		-1 if s is a prefix of t
#		0 if s is the same as t
#		1 if t is a prefix of s
#		2 if t strictly precedes s
acomp(s, t: Datum): int
{
	for(i:=0;;i++) {
		if(i == len s && i == len t)
			return 0;
		else if(i == len s)
			return -1;
		else if(i == len t)
			return 1;
		else if(s[i] != t[i])
			break;
	}
	if(s[i] < t[i])
		return -2;
	return 2;
}

prefixlen(s, t: array of byte): int
{
	l := 0;
	if(len s < len t)
		l = len s;
	else
		l = len t;
	for(i :=0; i < l; i++)
		if(s[i] != t[i])
			return i;
	return l;
}
