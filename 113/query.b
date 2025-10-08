implement Triplestore, Command;
include "sys.m";
include "draw.m";
include "turtle.m";
include "query.m";
include "hash.m";

Command:module{init:fn(c:ref Draw->Context, argv:list of string);};

sys: Sys;
FD: import sys;
turtle: Turtle;
hash: Hash;
HashTable, HashVal: import hash;

triples: list of ref Triple;
DBG: con 0;

modinit()
{
	sys = load Sys Sys->PATH;
	turtle = load Turtle Turtle->PATH;
	turtle->init();
	hash = load Hash Hash->PATH;
}

init(nil: ref Draw->Context, argv: list of string)
{
	modinit();
	argv = tl argv;
	if(len argv == 0) {
		sys->print("args?\n");
		exit;
	}
	open(hd argv);

	sel : list of string;
	whe : list of Triple;
	sel = "?title" :: "?name" :: nil;
	whe = 	Triple("?book", "http://purl.org/dc/elements/1.1/title", "?title") ::
		Triple("?book", "http://purl.org/dc/elements/1.1/url", "?url") ::
		Triple("?url", 	"http://purl.org/dc/elements/1.1/title", "?name") :: nil;

	stmt := prepare(sel, whe);

	while((result := step(stmt)) != nil)
	for(ls:=result; ls != nil; ls = tl ls)
		sys->print("%s\n", hd ls);
}

open(file: string)
{
	if (sys == nil)
		modinit();
	triples = turtle->read(file);
	if(DBG)sys->print("read %d triples\n", len triples);
}

OBJ, PRED, SUBJ: con 1<<iota;
x := array[256] of ref Triple;
di := array[256] of list of ref Triple;
l := 1;
n := 75;
solutions := 0;
lcnt := array[256] of { * => 0};

vars := array[256] of int;
symtab: ref HashTable;
xtri := array[256] of Triple;

addsym(s: string, v: int)
{
	if(DBG)sys->print("addsym %s %x\n", s, v);
	hv := symtab.find(s);
	if(hv==nil)
		symtab.insert(s, HashVal(v,0.0,nil));
}

prepare(select:list of string, where:list of Triple): ref Statement
{
	st := ref Statement(select, where);
	n = len where;
	i := 0;
	symtab = hash->new(256);
	for (ls := where; ls != nil; ls = tl ls) {
		t := hd ls;
		i++;
		var := 0;
		(s, p, o) := (t.s, t.p, t.o);
		if(len s > 0 && s[0] == '?') {
			addsym(s,i);
			var |= SUBJ;
		}
		if(len p > 0 && p[0] == '?') {
			addsym(p, i);
			var |= PRED;
		}
		if(len o > 0 && o[0] == '?') {
			addsym(o, i);
			var |= OBJ;
		}
		xtri[i] = t;
		vars[i] = var;
	}

	return st;
}

first := 0;
step(stmt: ref Statement): list of string
{
	if(first == 0){
		updated();
	}
	rc := btrk(first);
	if(DBG)sys->print("btrk returned %d\n", rc);
	first = 1;
	result : list of string;
	if(rc){
		for(ls := stmt.select; ls != nil; ls = tl ls) {
			sym := hd ls;
			hv := symtab.find(sym);
			if(hv != nil){
				xt := xtri[hv.i];
				if(DBG)sys->print("step1 %s %x: %s, %s, %s\n", sym, hv.i, xt.s,xt.p,xt.o);
				var := vars[hv.i];
				if(DBG)sys->print("step2 %x: %s, %s, %s\n", var, x[hv.i].s, x[hv.i].p, x[hv.i].o);
				if((var & SUBJ) && xtri[hv.i].s == sym)
					result = x[hv.i].s :: result;
				if((var & PRED) && xtri[hv.i].p == sym)
					result = x[hv.i].p :: result;
				if((var & OBJ) && xtri[hv.i].o == sym)
					result = x[hv.i].o :: result;
			}
		}
	}
	rev : list of string;
	for(ls := result; ls != nil; ls = tl ls)
		rev = hd ls :: rev;
	if(DBG)sys->print("step results %d\n", len result);
	return rev;
}

# Inversions to index
# s,p; s,o; p,o; s; p; o.
rdf(s,p,o: string, var: int, lt: list of ref Triple): list of ref Triple
{
	nl : list of ref Triple;
	if(DBG)sys->print("rdf %x s:%s p:%s o:%s\n", var, s, p, o);
	for(ls := lt; ls != nil; ls = tl ls) {
		t := hd ls;
		(s1, p1, o1) := (t.s, t.p, t.o);

		case var {
			0 =>	if(s1 == s && p1 == p && o1 == o)
					nl = t :: nl;
			1 =>	if(s1 == s && p1 == p)
					nl = t :: nl;
			2 =>	if(s1 == s && o1 == o)
					nl = t :: nl;
			3 =>	if(s1 == s)
					nl = t :: nl;
			4 =>	if(p1 == p && o1 == o)
					nl = t :: nl;
			5 =>	if(p1 == p)
					nl = t :: nl;
			6 =>	if(o1 == o)
					nl = t :: nl;
			7 =>	nl = t :: nl;
		}
	}
	return nl;
}

getfield(s: string, i: int): string
{
	xt := xtri[i];
	if(DBG)sys->print("getfield: %s %d\n", s, i);
	if(s == xt.s)
		return x[i].s;
	if(s == xt.p)
		return x[i].p;
	if(s == xt.o)
		return x[i].o;
	if(DBG)sys->print("warn: getfield: not found %s\n", s);
	return nil;
}

# on update() substitute any symbols already found into the query triple.
# query the triplestore.
# set the domain di[] with the result list triples.
updated(): int
{
	(s, p, o) := xtri[l];
	var := vars[l];
	hv : ref HashVal;

	if(DBG)sys->print("update %s %s %s var %x lev %d\n", s, p, o, var, l);
	if(l > n)
		return 0;
	if(var&SUBJ) {
		hv = symtab.find(s);
		if(hv != nil && hv.i < l) {
			var ^= SUBJ;
			s = getfield(s, hv.i);  #Which field is it? Could be any.
		}
	}
	if(var&PRED) {
		hv = symtab.find(p);
		if(hv != nil && hv.i < l) {
			var ^= PRED;
			p = getfield(p, hv.i);
		}
	}
	if(var&OBJ) {
		hv = symtab.find(o);
		if(DBG)sys->print("upd hv %d lev %d var %x\n", hv.i, l, var);
		if(hv != nil && hv.i < l){
			var ^= OBJ;
			o = getfield(o, hv.i);
		}
	}
	di[l] = rdf(s,p,o,var,triples);
	if(DBG)sys->print("rdf found %d results at level %d var %x\n", len di[l], l, var);
	x[l] = nil;

	return 0;
}

pass():int
{
	return x[l] != nil;
}

btrk(reenter: int): int
{
	backtrack := 0;
	b2: for(;;) {
		if (reenter || l > n) {
			#visit();
			if(!reenter)
				return 1;
			reenter = 0;
			backtrack = 1;
		} else if (di[l] != nil) {
			x[l] = hd di[l];
			di[l] = tl di[l];
		} else
			x[l] = nil;
		if(0)sys->print("l=%d x %d\n", l, backtrack);
		lcnt[l]++;

		b3: for(;;) {
			if (!backtrack) {
				if (pass()) {
					l++;
					updated();
					continue b2;
				}
			}
			b4: for(;;) {
				if (!backtrack) {
					if (di[l] != nil){
						x[l] = hd di[l];
						di[l] = tl di[l];
						continue b3;
					}
				}
				backtrack = 0;
				di[l] = nil;
				l--;
				if (l > 0)
					continue b4;
				else
					return 0;
			}
		}
	}
}
