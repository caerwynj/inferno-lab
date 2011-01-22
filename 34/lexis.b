implement Lexis;

include "sys.m";
	sys: Sys;
include "lexis.m";
include "cache.m";
include "btree.m";
	btreem: Btreem;
	Sequence, Btree, Block, Entry, Cursor: import btreem;
include "util.m";
	util: Util;
	acomp, Datum,p32,g32: import util;
include "names.m";
	names: Names;

bt: ref Btree;
seqno: ref Sequence;
schema: list of ref Rule;		# will need to lock this
stderr: ref Sys->FD;

LOCKDIR: con "/lib/lexis/";
SEQ: con 0;

init(file: string)
{
	sys = load Sys Sys->PATH;
	util = load Util Util->PATH;
	btreem = load Btreem Btreem->PATH;
	names = load Names Names->PATH;

	btreem->init();
	lockfile := LOCKDIR + names->basename(file, nil);
	(n, nil) := sys->stat(lockfile);
	if(n == -1){
		fd := sys->create(lockfile, Sys->OREAD, 8r664);
		if(fd == nil){
			sys->fprint(sys->fildes(2), "error creating lockfile %s\n", lockfile);
			exit;
		}
		fd = nil;
	}
	bt = btreem->open(file, Sys->ORDWR, lockfile);
	if(bt == nil) {
		sys->fprint(sys->fildes(2), "error opening btree\n");
		exit;
	}
	seqno =  Sequence.init(bt, SEQ);
#	while(seqno.current() < 10)
#		seqno.next();
	
	stderr = sys->fildes(2);
	#bootstrap
	loadschema();
	# the Objects need to be stored in the database too.
	# make sure the following exist with contant oid's
	Rule.mk("Object", Attribute);
	Rule.mk("Relation", Category); 
	Rule.mk("Category", Category); 
	Rule.mk("Attribute", Category);
	Rule.mk("Schema", Category);
	Rule.mk("Srule", Relation);
#	printschema(schema);
}

access(nil: array of byte): ref Btree
{
	return bt;
}

mkobjectid(): int
{
	n := seqno.next();
	s := sys->sprint("ID:%d", n);
	addconcrete(n, Object, array of byte s);
	return n;
}

getobjectid(s: string, create:int): int
{
	n := getoid(s);
	if(n == 0 && create) {
		n = seqno.next();
		addconcrete(n, Object, array of byte s);
	}
	return n;
}

Fact.put(f: self ref Fact)
{
	pick p := f {
	Category =>
		c := findschema(p.c);
		if(c != nil && c.typ == Category)
			addcategory(p.x, p.c);
		else if(p.c == Relation || p.c == Attribute || p.c == Category)
			addcategory(p.x, p.c);
		else
			sys->fprint(stderr, "bad category %d\n", p.c);
	Relation =>
		c := findschema(p.r);
		if(c != nil && c.typ == Relation)
			addfact(p.x, p.r, p.y, nil);
		else
			sys->fprint(stderr, "bad relation %d\n", p.r);
	Attribute =>
		c := findschema(p.r);
		if (c != nil && c.typ == Attribute)
			addconcrete(p.x, p.r, p.v);
		else
			sys->fprint(stderr, "bad attribute %d\n", p.r);
	}
}

Fact.print(f: self ref Fact)
{
	pick m := f {
	Category =>
		c := findschema(m.c);
		s := getname(m.x);
		sys->print("%s %s\n", s, c.name);
	Relation =>
		r := findschema(m.r);
		x := getname(m.x);
		y := getname(m.y);
		sys->print("%s %s %s\n", x, r.name, y);
	Attribute =>
		r := findschema(m.r);
		x := getname(m.x);
		sys->print("%s %s '%s'\n", x, r.name, string m.v);
	}
}

Fact.mk(b: array of byte): ref Fact
{
	fact :ref Fact;
	a := g32(b, 0);
	c := findschema(-a);	# Inverted id's only
	if(c == nil){   # a is abstract object
		n := g32(b, 4);
		c = findschema(n);
		if(c == nil){
			c = findschema(-n);
			if(c != nil && c.typ == Relation)
				fact = ref Fact.Relation(g32(b, 8), c.oid, a);
			else
				sys->fprint(stderr, "bad fact\n");
		}else 
			case c.typ {
			Attribute =>
				fact = ref Fact.Attribute(a, c.oid, b[8:]);
			Category =>
				fact = ref Fact.Category(a, c.oid);
			Relation =>
				fact = ref Fact.Relation(a, c.oid, g32(b, 8)); 
			}
	}else {
		case c.typ {
		Attribute =>
			fact = ref Fact.Attribute(g32(b, len b - 4), c.oid, b[4:len b - 4]);
		Category =>
			fact = ref Fact.Category(g32(b, 4), c.oid);
		Relation =>
			sys->fprint(stderr, "Relation type %s can't be in first position\n", c.name); # error
		}
	}
	return fact;
}

Fact.pack(f: self ref Fact, nil: int, nil: int): array of byte
{
	pick p:=f {
	Attribute =>
		;
	Category =>
		;
	Relation =>
		;
	}
	return nil;
}

# aRb and bRa
addfact(a, b, c: int, atts: array of byte)
{
	buf1 := array[4*3] of byte;
	buf2 := array[4*3] of byte;

	p32(buf1, 0, a);
	p32(buf1, 4, b);
	p32(buf1, 8, c);
	p32(buf2, 0, c);
	p32(buf2, 4, -b);
	p32(buf2, 8, a);
	bt.insert(buf1, atts);
	bt.insert(buf2, atts);
}

# aRv and Rva
addconcrete(a: int, rel: int, val: array of byte)
{
	buf := array[len val + 8] of byte;
	p := buf;
	p32(p, 0, a);
	p32(p, 4, rel);
	p = p[8:];
	p[0:] = val;
	bt.insert(buf, nil);

	p = buf;
	p32(p, 0, -rel);
	p = p[4:];
	p[0:] = val;
	p = p[len val:];
	p32(p, 0, a);
	bt.insert(buf, nil);
}

# aC and Ca
addcategory(a: int, c: int)
{
	buf := array[8] of byte;
	p32(buf, 0, a);
	p32(buf, 4, c);
	bt.insert(buf, nil);

	p32(buf, 0, -c);
	p32(buf, 4, a);
	bt.insert(buf, nil);
}

getname(oid: int): string
{
	buf:=array[8] of byte;
	p32(buf, 0, oid);
	p32(buf, 4, Object);
	return string get(buf);
}

get(prefix: Datum): Datum
{
	(k, nil) := bt.search(prefix);
	if(k != nil)
		return k[len prefix:];
	return nil;
}

getfirst(prefix: Datum): Datum
{
	(k, nil) := bt.search(prefix);
	return k;
}

getoid(name: string): int
{
	val  := array of byte name;
	key := packna(-Object, val);
	cur := Cursor.locate(bt, key);
	loop: while((e := cur.next()) != nil && acomp(key, e.key) != -2){
		f := Fact.mk(e.key);
		pick m:=f {
		Attribute =>
			if(acomp(m.v, val) == 0)
				return m.x;
		* =>
			break loop;
		}
	}
	return 0;
}

packnan(n: int, d: array of byte, m: int): array of byte
{
	buf := array[len d + 8] of byte;
	p := buf;
	p32(p, 0, n);
	p = p[4:];
	p[0:] = d;
	p = p[len d:];
	p32(p, 0, m);
	return buf;
}

packnna(n: int, m: int, d: array of byte): array of byte
{
	buf := array[len d + 8] of byte;
	p := buf;
	p32(p, 0, n);
	p32(p, 4, m);
	p = p[8:];
	p[0:] = d;
	return buf;
}

packna(n: int, d: array of byte): array of byte
{
	prefix := array[len d + 4] of byte;
	p32(prefix, 0, n);
	p := prefix[4:];
	p[0:] = d;
	return prefix;
}

packnn(n: int, m: int): array of byte
{
	prefix := array[8] of byte;
	p32(prefix, 0, n);
	p32(prefix, 4, m);
	return prefix;
}

packan(d: array of byte, n: int): array of byte
{
	prefix := array[len d + 4] of byte;
	prefix[0:] = d;
	p32(prefix, len d, n);
	return prefix;
}

close()
{
	bt.close();
	kill(sys->pctl(0, nil));
}

kill(pid: int)
{
	path := sys->sprint("#p/%d/ctl", pid);
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

loadschema()
{
	key := array[4] of byte;
	p32(key, 0, -Schema);
	cur := Cursor.locate(bt, key);
	while((e := cur.next()) != nil && acomp(key, e.key) != -2) {
		oid := g32(e.key, 4);
		name := getname(oid);
		buf := get(packnn(oid, Srule));
		typ := g32(buf, 0);
		schema = ref Rule(name, typ, oid) :: schema;
	}
}

tname := array[] of {"Null", "Object", "Relation", "Category", "Attribute", "Schema", "Srule"};
printschema(s: list of ref Rule)
{
	for(; s != nil; s = tl s){
		p := hd s;
		sys->print("%s typ:%s ID:%d\n", p.name, tname[p.typ], p.oid);
	}
}

findschema(oid: int): ref Rule
{
	for(l := schema; l != nil; l = tl l)
		if(oid == (hd l).oid)
			return hd l;
	return nil;
}

Rule.mk(name: string, typ: int): ref Rule
{
	oid := getobjectid(name, 1);
	rule := ref Rule(name, typ, oid);
	c := findschema(rule.oid);
	if(c != nil)
		return c;
	else {
		schema = rule :: schema;
		addfact(oid, Srule, typ, nil);
		addcategory(oid, Schema);
	}
	return rule;
}

Position.mk(prefix: array of byte): ref Position
{
	p := ref Position(Cursor.locate(bt, prefix));
	return p;
}

Position.next(p: self ref Position): ref Fact
{
	e := p.pos.next();
	if(e == nil)
		return nil;
	else
		return Fact.mk(e.key);
}
