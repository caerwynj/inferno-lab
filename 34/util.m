Util: module {
	PATH: con "/dis/folkfs/util.dis";
	BIT8SZ:	con 1;
	BIT16SZ:	con 2;
	BIT32SZ:	con 4;
	BIT64SZ:	con 8;
	Datum: type array of byte;

	edist: fn(s, t:string):int;
	p32: fn(a: array of byte, o: int, v: int): int;
	p64: fn(a: array of byte, o: int, b: big): int;
	pvint: fn(a: array of byte, o: int, v: int): int;
	g32: fn(f: array of byte, i: int): int;
	g64: fn(f: array of byte, i: int): big;
	gvint: fn(f: array of byte, i: int):int;
	acomp: fn(s, t: Datum): int;
	prefixlen: fn(s, t: array of byte): int;
};
