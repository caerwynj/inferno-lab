Lexis: module
{
	PATH: con "/dis/folkfs/lexis.dis";

	Object: 	con 1;
	Relation:	con 2;
	Category:	con 3;
	Attribute:	con 4;
	Schema:	con 5;
	Srule:	con 6;

	Rule: adt {
		name: string;
		typ: int;
		oid: int;
		mk: fn(name: string, typ: int): ref Rule;
	};

	Fact: adt {
		x: int;
		pick {
		Category =>
			c: int;
		Relation =>
			r,y: int;
		Attribute =>
			r: int;
			v: array of byte;
		}
		put:	fn(f: self ref Fact);
		print: fn(f: self ref Fact);
		mk: fn(b: array of byte): ref Fact;
		pack: fn(f: self ref Fact, inv: int, prefix: int): array of byte;
		# istrue: fn(f: self ref Fact): int;
	};

	Position: adt {
		pos: ref Btreem->Cursor;
		mk:	fn(prefix: array of byte): ref Position;
		next:	fn(p: self ref Position): ref Fact;
	};

	Dat: adt {
		pick {
		Int =>
			o: int;
		Array =>
			a: array of byte;
		}
	};

	init:		fn(file: string);
	access:	fn(key: array of byte): ref Btreem->Btree;
	getobjectid: 	fn(key: string, create:int): int;
	mkobjectid:	fn(): int;
	getname:	fn(oid: int): string;
	get:		fn(prefix: array of byte): array of byte;	#only for unique prefix
	getfirst:		fn(prefix: array of byte): array of byte;	#only for unique prefix
	close:	fn();
	packna:	fn(n: int, d: array of byte): array of byte;
	packnn:	fn(n: int, m: int): array of byte;
	findschema:	fn(oid: int): ref Rule;
};
