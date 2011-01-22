Query: module
{
	PATH: con "/dis/folkfs/query.dis";
	SS: type chan of list of ref Lexis->Dat;

	query: fn(q: string): (int, chan of list of string);
	kill: fn(pid: int);
	init: fn(nlex: Lexis);
};
