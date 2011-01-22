Regx : module {
	PATH : con "regx.dis";
	Infinity : con 16r7fffffff; 	# huge value for regexp address
	FALSE, TRUE, XXX : con iota;
	NRange : con 10;
	Range : adt {
		q0 : int;
		q1 : int;
	};
	Rangeset : type array of Range;
	Text : adt {
		name: string;
		io: ref Bufio->Iobuf;
		nc: int;
		q0, q1: int;
		readc : fn(t : self ref Text, n : int) : int;
		new: fn(f: string): ref Text;
	};

	init : fn();
	rxcompile: fn(r : string) : int;
	rxexecute: fn(t : ref Text, r: string, startp : int, eof : int) : (int, Rangeset);
	rxbexecute: fn(t : ref Text, startp : int) : (int, Rangeset);
};
