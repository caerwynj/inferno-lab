implement Command;

include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "sh.m";

# power series package
# a power series is a channel, along which flow the coefficients
# Translated from Rob Pike's squint, a newsqueak interpreter.
# See "Squinting the Power Series" by Doug McIlroy

rat : adt { 
	num, den: int;	# numerator, denominator
};

pol: type array of rat;
PS: type chan of rat;
PS2: type array of PS;

# Conventions
# Upper-case for power series.
# Lower-case for rationals.
# Input variables: U,V,...
# Output variables: ...,Y,Z

zero: rat;
one: rat;
Ones: PS;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	args = tl args;

	zero = inttorat(0);
	one = inttorat(1);
	Ones = Rep(one);
	c := chan of int;
	spawn run(c);
	pid := <-c;
	<-c;
	kill(pid);
}

run(c: chan of int)
{
	c <-= sys->pctl(Sys->NEWPGRP, nil);
#	Printn(Binom(inttorat(20)), 20);
	Printn(Exp(Ones), 10);
#	Printn(Diff(Ones), 10);
	c<-=1;
	c<-=0;
}


kill(pid: int)
{
	path := sys->sprint("#p/%d/ctl", pid);
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

gcd(u: int, v: int): int
{
	if(u<0)
		return gcd(-u,v);
	else if(u>v)
		return gcd(v,u);
	else if(u==0)
		return v;
	else
		return gcd(v%u,u);
}

pairtorat(u:int,v:int):rat
{
	g:=gcd(u,v);
	if(v>=0)
		return rat(u/g,v/g);
	else
		return rat(-u/g,-v/g);
}

inttorat(u:int): rat
{
	return pairtorat(u,1);
}

ratprint(u:rat)
{
	if(u.den==1)
		print("%d ", u.num);
	else
		print("%d/%d ", u.num, u.den);
}

add(u:rat,v:rat):rat
{
	return pairtorat(u.num*v.den+v.num*u.den,u.den*v.den);
}

mul(u:rat,v:rat):rat
{
	return pairtorat(u.num*v.num,u.den*v.den);
}

neg(u:rat):rat
{
	return pairtorat(-u.num,u.den);
}

sub(u:rat,v:rat):rat
{
	return add(u,neg(v));
}

inv(u:rat):rat
{
	return pairtorat(u.den,u.num);
}


Print(U: PS)
{
	for(;;)
		ratprint(<-U);
}

Printn(U: PS, n: int)
{
	for(; n>0;n--)
		ratprint(<-U);
	print("\n");
}

# Power-series constructors return channels on which power
# series flow.  They start an encapsulated generator that
# puts the terms of the series on the channel.
# Often the generator is anonymous [not in limbo]; but some generators
# are useful in their own right (e.g. split, rep)

# add two power series

Add(U:PS, V:PS): PS
{
	Z := chan of rat;
	spawn Addp(U,V,Z);
	return Z;
}

Addp(U:PS, V:PS, Z: PS)
{
	for(;;)
		Z <-= add(<-U, <-V);
}

Cmul(c: rat, U:PS):PS
{
	Z := chan of rat;
	spawn Cmulp(c, U, Z);
	return Z;
}

Cmulp(c: rat, U:PS, Z:PS)
{
	for(;;)
		Z<-=mul(c, <-U);
}

Sub(U:PS, V:PS): PS
{
	return Add(U, Cmul(neg(one), V));
}

copy(U:PS, Z:PS)
{
	for(;;)
		Z<-=<-U;
}

Shift(c:rat, U:PS):PS
{
	Z := chan of rat;
	spawn Shiftp(c, U, Z);
	return Z;
}

Shiftp(c:rat, U:PS, Z:PS)
{
	Z<-=c;
	spawn copy(U,Z);
}

# Multiply by monomial x^n
# [cheaper than Mul(Mon(intorat(1),n),U)]

Monmul(U:PS, n:int):PS
{
	Z := chan of rat;
	spawn Monmulp(U, n, Z);
	return Z;
}

Monmulp(U:PS, n:int, Z:PS)
{
	for(; n>0; n--)
		Z<-=zero;
	spawn copy(U,Z);
}

# multiply by x

Xmul(U:PS):PS
{
	return Monmul(U,1);
}

# repeat the constant c

rep(c: rat, Z:PS)
{
	for(;;)
		Z<-=c;
}

Rep(c:rat):PS
{
	Z := chan of rat;
	spawn rep(c, Z);
	return Z;
}

# Monomial c*x^n

Mon(c:rat, n:int):PS
{
	Z := chan of rat;
	spawn Monp(c, n, Z);
	return Z;
}

Monp(c: rat, n: int, Z:PS)
{
	for(; n>0; n--)
		Z<-=zero;
	Z<-=c;
	rep(zero,Z);
}

Con(c:rat):PS
{
	return Shift(c, Rep(zero));
}

Poly(a: array of rat):PS
{
	Z: chan of rat;
	spawn Polyp(a, Z);
	return Z;
}

Polyp(a: array of rat, Z: PS)
{
	for(i:=0;i<len a;i++)
		Z<-=a[i];
	spawn copy(Rep(zero), Z);
}

Split(U:PS):PS2
{
	ZZ := array[] of {chan of rat, chan of rat};
	spawn Splitp(U, ZZ);
	return ZZ;
}

Splitp(U:PS, ZZ:PS2)
{
	u:= <-U;
	i: int;
	alt {
	ZZ[0] <-=u =>
		i = 0;
	ZZ[1]  <-=u =>
		i = 1;
	}
	YY := Split(U);
	spawn copy(YY[i], ZZ[i]);
	ZZ[1-i] <-= u;
	spawn copy(YY[1-i], ZZ[1-i]);
}

# multiply. The algorithm is
# 	let U = u + x*UU
#	let V = v + x*VV
#	then UV = u*v + x*(u*VV+v*UU) + x*x*UU*VV

Mul(U:PS, V:PS): PS
{
	Z := chan of rat;
	spawn Mulp(U,V,Z);
	return Z;
}

Mulp(U:PS, V:PS, Z:PS)
{
	u := <-U;
	v := <-V;
	Z <-= mul(u,v);
	UU := Split(U);
	VV := Split(V);
	W := Add(Cmul(u, VV[0]), Cmul(v, UU[0]));
	Z <-= <-W;
	spawn copy(Add(W, Mul(UU[1], VV[1])), Z);
}

# derivative

Diff(U:PS): PS
{
	Z := chan of rat;
	spawn Diffp(U, Z);
	return Z;
}

Diffp(U:PS, Z:PS)
{
	<-U;
	for(i:=1; ; i++)
		Z <-= mul(inttorat(i), <-U);
}

# integrate, with const of integration

Integ(c: rat, U:PS):PS
{
	Z := chan of rat;
	spawn Integp(U, Z);
	return Shift(c, Z);
}

Integp(U:PS, Z:PS)
{
	for(i:=1; ; i++)
		Z <-=mul(pairtorat(1, i), <-U);
}

# binomial theorem (1+x)^c

Binom(c: rat):PS
{
	Z := chan of rat;
	spawn Binomp(c, Z);
	return Z;
}

Binomp(c: rat, Z:PS)
{
	n := 1;
	t := inttorat(1);
	for(;;){
		Z <-=t;
		t = mul(mul(t,c), pairtorat(1,n));
		c = sub(c,one);
		n++;
	}
}

# reciprocal of a power series
#	let U = u + x*UU
#	let Z = z + x*ZZ
#	(u+x*UU)*(z+x*ZZ) = 1
#	z = 1/u
#	ZZ = -(z*UU + x*UU*ZZ)/u

Recip(U:PS):PS
{
	ZZ := array[] of {chan of rat, chan of rat};
	spawn Recipp(U, ZZ);
	return ZZ[1];
}

Recipp(U:PS, ZZ:PS2)
{
	z :=inv(<-U);
	UU := Split(Cmul(neg(z), U));
	spawn Splitp(Shift(z, Add(Cmul(z, UU[0]), Xmul(Mul(UU[1], ZZ[0])))), ZZ);
}

# exponential of a power series with constant term 0
# (nonzero constant term would make nonrational coefficients)
# bug: the constant term is simply ignored
#	Z = exp(U)
#	DZ = Z*DU
#	integrate to get Z

Exp(U:PS):PS
{
	ZZ := array[] of {chan of rat, chan of rat};
	spawn Splitp(Integ(one, Mul(ZZ[0], Diff(U))), ZZ);
	return ZZ[1];
}

# substitute V for x in U
#	let U = u + xUU
# 	then S(U,V) = u + V*S(V,UU)    

Subst(U:PS, V:PS):PS
{
	Z := chan of rat;
	spawn Substp(U, V, Z);
	return Z;
}

Substp(U:PS, V:PS, Z:PS)
{
	Z <- = <-U;
	spawn copy(Mul(V, Subst(U,V)),Z);
}
