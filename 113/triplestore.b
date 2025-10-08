implement Triplestore;
include "sys.m";
include "draw.m";
include "query.m";
include "hash.m";
include "sqlite.m";

sys: Sys;
print, FD: import sys;
hash: Hash;
HashTable, HashVal: import hash;
sqlite: Sqlite;
Conn, Stmt: import sqlite;

triples: list of ref Triple;
DBG: con 0;

db: ref Conn;

modinit()
{
	sys = load Sys Sys->PATH;
	hash = load Hash Hash->PATH;
	sqlite = load Sqlite Sqlite->PATH;
}

open(file: string)
{
	rc: int;

	if (sys == nil)
		modinit();
	print("open database\n");
	(db, rc) = sqlite->open(file);
	if(db != nil) 
		print("db not nil, %d\n", rc);
	else {
		print("db nil, %d\n", rc);
		return;
	}
}

OBJ, PRED, SUBJ: con 1<<iota;
x := array[256] of ref Triple;
di := array[256] of ref Stmt;
l := 1;
n := 75;
solutions := 0;
lcnt := array[256] of { * => 0};

vars := array[256] of int;
symtab: ref HashTable;
xtri := array[256] of Triple;

addsym(s: string, v: int)
{
	if(DBG)print("addsym %s %x\n", s, v);
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
	if(DBG)print("btrk returned %d\n", rc);
	first = 1;
	result : list of string;
	if(rc){
		for(ls := stmt.select; ls != nil; ls = tl ls) {
			sym := hd ls;
			hv := symtab.find(sym);
			if(hv != nil){
				xt := xtri[hv.i];
				if(DBG)print("step1 %s %x: %s, %s, %s\n", sym, hv.i, xt.s,xt.p,xt.o);
				var := vars[hv.i];
				if(DBG)print("step2 %x: %s, %s, %s\n", var, x[hv.i].s, x[hv.i].p, x[hv.i].o);
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
	if(DBG)print("step results %d\n", len result);
	return rev;
}

# Inversions to index
# s,p; s,o; p,o; s; p; o.
rdf(s,p,o: string, var: int, lt: list of ref Triple): list of ref Triple
{
	nl : list of ref Triple;
	if(DBG)print("rdf %x s:%s p:%s o:%s\n", var, s, p, o);
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

prep(s,p,o: string, var: int): ref Stmt
{
	sql := "select * from triple where ";
	case var {
		0 =>	sql += "s = ?1 and p = ?2 and o = ?3";
		1 =>	sql += "s = ?1 and p = ?2";
		2 =>	sql += "s = ?1 and o = ?3";
		3 =>	sql += "s = ?1";
		4 =>	sql += "p = ?2 and o = ?3";
		5 =>	sql += "p = ?2";
		6 =>	sql += "o = ?3";
		7 =>	;
	}
	print("prepare stmt\n");
	(stmt, rc) := sqlite->prepare(db, sql);
	print("rc %d\n", rc);

	if(var&SUBJ)
		sqlite->bind_text(stmt, 1, s);
	if(var&PRED)
		sqlite->bind_text(stmt, 2, p);
	if(var&OBJ)
		sqlite->bind_text(stmt, 3, o);

	return stmt;
}


getfield(s: string, i: int): string
{
	xt := xtri[i];
	if(DBG)print("getfield: %s %d\n", s, i);
	if(s == xt.s)
		return x[i].s;
	if(s == xt.p)
		return x[i].p;
	if(s == xt.o)
		return x[i].o;
	if(DBG)print("warn: getfield: not found %s\n", s);
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

	if(DBG)print("update %s %s %s var %x lev %d\n", s, p, o, var, l);
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
		if(DBG)print("upd hv %d lev %d var %x\n", hv.i, l, var);
		if(hv != nil && hv.i < l){
			var ^= OBJ;
			o = getfield(o, hv.i);
		}
	}
	di[l] = prep(s,p,o,var);
	#if(DBG)print("rdf found %d results at level %d var %x\n", len di[l], l, var);
	x[l] = nil;

	return 0;
}

pass():int
{
	return x[l] != nil;
}

next(): int
{
	s,p,o : string;
	stmt := di[l];

	rc := sqlite->step(stmt);
	if(DBG)print("next: rc %d\n", rc);
	if(rc == Sqlite->DONE) {
		x[l] = nil;
		return 0;
	} else if (rc == Sqlite->ROW) {
		s = sqlite->column_text(stmt,0);
		p = sqlite->column_text(stmt,1);
		o = sqlite->column_text(stmt,2);
		x[l] = ref Triple(s,p,o);
		return 1;
	} else {
		print("next: sqlite error %d\n", rc);
		x[l] = nil;
	}
	return 0;
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
		} else
			next();
		if(0)print("l=%d x %d\n", l, backtrack);
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
					if (next())
						continue b3;
				}
				backtrack = 0;
				sqlite->finalize(di[l]);
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
