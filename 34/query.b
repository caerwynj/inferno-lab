implement Query;

include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "cache.m";
include "btree.m";
include "lexis.m";
	lex: Lexis;
	Fact, Position, Dat: import lex;
include "query.m";
include "util.m";
	util: Util;
	acomp, p32, g32: import util;
include "string.m";
	str: String;

Sym: adt {
	name: string;
	f: ref fn(U: SS): SS;
};

stderr: ref Sys->FD;
stdin: ref Sys->FD;
nresults: int;
symtab: array of Sym;

init(nlex: Lexis)
{
	sys = load Sys Sys->PATH;
	lex = nlex;
	util = load Util Util->PATH;
	str = load String String->PATH;

	symtab = array[] of  {
		Sym("aC", aC),
		Sym("aRy", aRy),
		Sym("a?", a_),
		Sym("?C", _C),
		Sym("aR?", aR_),
		Sym("?Ra", _Ra),
		Sym("a??", a__),
		Sym("?Rv", _Rv),
		Sym("?Rvv", _Rvv),
		Sym("pop", Pop),
		Sym("dup", Dup),
#		Sym("print", Print),
#		Sym("putC", nil),
#		Sym("putR", nil),
#		Sym("putA", nil),
#		Sym("del", nil),
		Sym("rev", Rev),
		Sym(nil, nil)
	};

	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	nresults = 100;
}

cmdlookup(c: string): int
{
	i: int;

	for(i=0; symtab[i].name != nil; i++)
		if(symtab[i].name == c)
			return i;
	return -1;
}

kill(pid: int)
{
	path := sys->sprint("#p/%d/ctl", pid);
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

query(q: string): (int, chan of list of string)
{
	Z := chan of chan of list of string;
	c := chan of int;
	args := str->unquoted(q);
	spawn run(args, c, Z);
	pid := <-c;
	V := <-Z;
	return (pid, V);
}

run(args: list of string, c: chan of int, Z: chan of chan of list of string)
{
	c <-= sys->pctl(Sys->NEWPGRP, nil);
	U := eval(args);
	Z <-= U;
	c <-=0;
}

eval(sl: list of string): chan of list of string
{
	U := Start();
	for(; sl != nil; sl = tl sl){
		i: int;
		i = cmdlookup(hd sl);
		if (i >= 0){
			f := symtab[i].f;
			U = f(U);
		}else {
			s := hd sl;
			if(s[0] == ':')
				U = Push(ref Dat.Array(array of byte s[1:]), U);
			else {
				i = lex->getobjectid(hd sl, 0);
				if(i == 0)
					U = Push(ref Dat.Array(array of byte hd sl), U);
				else
					U = Push(ref Dat.Int(i), U);
			}
		}
	}
	return toString(U);
}

Push(sym: ref Dat, U:SS): SS
{
	Z := chan of list of ref Dat;
	spawn Pushp(sym, U, Z);
	return Z;
}

Pushp(sym: ref Dat, U, Z: SS)
{
	for(;;){
		u := <-U;
		if(u == nil){
			u = sym :: u;
			Z <-= u;
			Z <-= nil;
			return;
		}
		u = sym :: u;
		Z <-= u;
	}
}

Pop(U:SS): SS
{
	Z := chan of list of ref Dat;
	spawn Popp(U, Z);
	return Z;
}

Popp(U,Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-= nil;
			return;
		}
		Z <-= tl u;
	}
}

Dup(U:SS):SS
{
	Z := chan of list of ref Dat;
	spawn Dupp(U, Z);
	return Z;
}

Dupp(U,Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-= nil;
			return;
		}
		u = hd u :: u;
		Z <-= u;
	}
}

Start():SS
{
	Z := chan of list of ref Dat;
	spawn start(Z);
	return Z;
}

start(Z:SS)
{
	Z <-= nil;
}

Rep(i: int): SS
{
	Z := chan of list of ref Dat;
	spawn rep(i, Z);
	return Z;
}

rep(i: int, Z:SS)
{
	for(;;)
		Z<-= ref Dat.Int(i) :: nil;
}

Rev(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn Revp(U, Z);
	return Z;

}

Revp(U, Z: SS)
{
	z : list of list of ref Dat;
	for(;;) alt{
	u := <-U =>
		if(u == nil){
			for( ; z != nil; z = tl z)
				Z <-= hd z;
			Z <-= nil;
			return;
		}
		z = u :: z;
	}
}

PutC(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn PutC_p(U, Z);
	return Z;
}

PutC_p(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil ){
			Z <-=nil;
			continue;
		}
#		c := hd u;
#		a := hd tl u;
#		(ref Fact.Category(a, c)).put();
		Z <-=u;
	}
}

toString(U: SS): chan of list of string
{
	Z := chan of list of string;
	spawn toStringp(U, Z);
	return Z;
}

toStringp(U: SS, Z: chan of list of string)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}
		l : list of string;
		for(;u != nil ;u = tl u){
			pick m:= hd u{
			Int =>
				s := lex->getname(m.o);
				l = s :: l;
			Array =>
				l = string m.a :: l;
			}
		}
		Z <-= l;
	}
}

Print(U: SS): SS
{
	for(j:=0;j<nresults;j++){
		u := <-U;
		if(u == nil)
			break;
		uu : list of ref Dat;
		for(; u != nil; u = tl u)
			uu = hd u :: uu;
		u = uu;
		for(;u != nil ;u = tl u){
		#	sys->print("looking for %d\n", hd u);
			pick m:= hd u{
			Int =>
				s := lex->getname(m.o);
				sys->print("%s ", s);
			Array =>
				sys->print("'%s' ", string m.a);
			}
		}
		sys->print("\n");
	}
	return nil;
}

aR_(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn aR_p(U, Z);
	return Z;
}

aR_p(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if (len u < 2)
			continue;
		r, x: int;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			r = m.o;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			x = m.o;
		}
		key := array[8] of byte;
		p32(key, 0, x);
		p32(key, 4, r);
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Relation =>
				if(m.x != x || r != m.r)
					break loop;
				Z <-= ref Dat.Int(m.y) :: u;
			Attribute =>
				if(m.x != x || r != m.r)
					break loop;
				Z <-= ref Dat.Array(m.v) :: u;
			* =>
				break;
			}
		}
	}
}

aRy(U:SS):SS
{
	Z := chan of list of ref Dat;
	spawn aRyp(U, Z);
	return Z;
}

aRyp(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 3)
			continue;
		r, x: int;
		key: array of byte;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			key = array[12] of byte;
			p32(key, 8, m.o);
		Array =>
			key = array[8 + len m.a] of byte;
			p := key[8:];
			p[0:] = m.a;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			r = m.o;
			p32(key, 4, r);
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			x = m.o;
			p32(key, 0, x);
		}
		dat := lex->getfirst(key);
		if(dat != nil)
			Z <-= ref Dat.Int(x) :: u;
	}
}

a_(U:SS):SS
{
	Z := chan of list of ref Dat;
	spawn a_p(U, Z);
	return Z;
}

a_p(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 1)
			continue;
		x: int;
		key: array of byte;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			key = array[4] of byte;
			x = m.o;
			p32(key, 0, m.o);
		Array =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Category =>
				if(m.x != x)
					break loop;
				Z <-= ref Dat.Int(m.c) :: u;
			* =>
				if(m.x != x)
					break loop;
			}
		}
	}
}

_C(U:SS):SS
{
	Z := chan of list of ref Dat;
	spawn _Cp(U, Z);
	return Z;
}

_Cp(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 1)
			continue;
		c: int;
		key: array of byte;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			key = array[4] of byte;
			c = m.o;
			p32(key, 0, -m.o);
		Array =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Category =>
				if(m.c != c)
					break loop;
				Z <-= ref Dat.Int(m.x) :: u;
			* =>
				break loop;
			}
		}
	}
}

_Ra(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn _Rap(U, Z);
	return Z;
}

_Rap(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 2)
			continue;
		key := array[8] of byte;
		r, y: int;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			y = m.o;
			p32(key, 0, y);
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			r = m.o;
			p32(key, 4, -r);
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Relation =>
				if(m.y != y || r != m.r)
					break loop;
				Z <-= ref Dat.Int(m.x) :: u;
			* =>
				break;
			}
		}
	}
}

a__(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn a__p(U, Z);
	return Z;
}

a__p(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if (len u < 1)
			continue;
		key := array[4] of byte;
		x: int;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			x = m.o;
			p32(key, 0, x);
		* =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Relation =>
				if(m.x == x)
					Z <-= ref Dat.Int(m.r) :: ref Dat.Int(m.y) :: u;
				else if(m.y == x)
					Z <-= ref Dat.Int(m.r) :: ref Dat.Int(m.x) :: u;
				else
					break loop;
			Attribute =>
				if(m.x != x)
					break loop;
				Z <-= ref Dat.Int(m.r) :: ref Dat.Array(m.v) :: u;
			Category =>
				if(m.x != x)
					break loop;
				Z <-= ref Dat.Int(m.c) :: u;
			}
		}
	}
}

aC(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn aCp(U, Z);
	return Z;
}

aCp(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 2)
			continue;
		ou := u;
		key := array[8] of byte;
		x, c: int;
		h := hd u;
		u = tl u;
		pick m:=h{
		Int =>
			c = m.o;
			p32(key, 4, c);
		* =>
			continue;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			x = m.o;
			p32(key, 0, x);
		* =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Category =>
				if(m.x == x && m.c == c)
					Z <-= ou;
				else
					break loop;
			* =>
				break loop;
			}
		}
	}
}

_Rv(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn _Rvp(U, Z);
	return Z;
}

_Rvp(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 2)
			continue;
		key :array of byte;
		r: int;
		v : string;
		h := hd u;
		u = tl u;
		pick m:=h{
		Array =>
			key = array[len m.a + 4] of byte;
			p := key[4:];
			p[0:] = m.a;
			v = string m.a;
		* =>
			continue;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			r = m.o;
			p32(key, 0, -r);
		* =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Attribute =>
				if(m.r == r && string m.v == v)
					Z <-= ref Dat.Int(m.x) :: u;
				else
					break loop;
			* =>
				break loop;
			}
		}
	}
}

_Rvv(U: SS): SS
{
	Z := chan of list of ref Dat;
	spawn _Rvvp(U, Z);
	return Z;
}

_Rvvp(U:SS, Z:SS)
{
	for(;;) alt {
	u := <-U =>
		if(u == nil){
			Z <-=nil;
			return;
		}else if(len u < 3)
			continue;
		key :array of byte;
		r: int;
		v2: string;
		h := hd u;
		u = tl u;
		pick m:=h{
		Array =>
			v2 =  string m.a;
		* =>
			continue;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Array =>
			key = array[len m.a + 4] of byte;
			p := key[4:];
			p[0:] = m.a;
		* =>
			continue;
		}
		h = hd u;
		u = tl u;
		pick m:=h{
		Int =>
			r = m.o;
			p32(key, 0, -r);
		* =>
			continue;
		}
		cur := Position.mk(key);
		loop: while((e := cur.next()) != nil){
			pick m:=e {
			Attribute =>
				if(m.r == r && string m.v <= v2)
					Z <-= ref Dat.Int(m.x) :: u;
				else
					break loop;
			* =>
				break loop;
			}
		}
	}
}
