implement Util;

include "util.m";

#Levenshtein distance
edist(s, t: string): int
{
	e := array[len s + 1] of {* => array[len t + 1] of  int};
	if(len s == 0)
		return len t;
	if(len t == 0)
		return len s;
	for(i:=0;i<=len s;i++) e[i][0] = i;
	for(j:=0;j<=len t;j++) e[0][j] = j;

	for(i=1;i<=len s;i++)
		for(j=1;j<=len t; j++)
			if(s[i-1] != t[i-1])
				e[i][j] = min(e[i-1][j], e[i][j-1], e[i-1][j-1])+1;
			else
				e[i][j] = min(e[i-1][j]+1, e[i][j-1]+1, e[i-1][j-1]);

	return e[len s][len t];
}

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

sjc(current: int, pair: array of int): int
{
	if(pair[0] == -1)
		return 0;
	else if(pair[1] == -1)
		if(pair[0] <= current)
			return 1;
		else
			return 0;
	else if(pair[0] <= current && current < pair[1])
		return 1;
	else if(pair[0] == current && current == pair[1])
		return 1;
	else
		return 0;
}

SEQ,NONSEQ,EFF: con (1<<iota);
# beg,end overlaps this,next
overlap(beg,end,this,next,flag: int):int
{
	if(flag & SEQ){
		if(next == -1)
			if(this <= beg)
				return 1;
			else
				return 0;
		if(this <= beg && beg < next)
			return 1;
		else if(this == beg && end == next)
			return 1;
		else if(this > beg && this < end)
			return 1;
		else
			return 0;
	}else if(flag & NONSEQ){
		return 1;
	}else if(flag & EFF){
		if(next == -1)
			if(this <= beg)
				return 1;
			else
				return 0;
		else if(this <= beg && beg < next)
			return 1;
		else if(this == beg && beg == next)
			return 1;
		else
			return 0;
	}
}

