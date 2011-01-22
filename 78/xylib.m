Xylib: module {
	PATH: con "/dis/xy/xylib.dis";
	Value: adt {
		getfd:	fn(v: self ref Value): ref Sys->FD;
		gets:	fn(v: self ref Value): string;
		getn:	fn(v: self ref Value): int;
		send:	fn(v: self ref Value, r: ref Value);
		typec: fn(v: self ref Value): int;
		discard: fn(v: self ref Value);
		pick {
		C =>
			i: ref Sh->Cmd;
		S =>
			i: string;
		N =>
			i: int;
		F =>
			i: ref Sys->FD;
		O =>
			i: chan of ref Value;
		
		}
	};
	init:			fn();
	typecompat:	fn(t, act: string): int;

	cmdusage:	fn(cmd, t: string): string;
	type2s:		fn(t: int): string;
	opttypes:		fn(opt: int, opts: string): (int, string);
	splittype:		fn(t: string): (int, string, string);

	
	Option: adt {
		opt: int;
		args: list of ref Value;
	};
};

Xymodule: module {
	types: fn(): string;
	init:	fn();
	run: fn(r: chan of ref Xylib->Value, opts: list of Xylib->Option, 
		args: list of ref Xylib->Value);
};
