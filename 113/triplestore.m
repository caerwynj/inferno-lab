Triplestore: module {
	PATH: con "/dis/lib/triplestore.dis";
	Triple:adt {
		s,p,o: string;
	};
	Statement:adt {
		select: list of string;
		where: list of Triple;
	};

	open:fn(file: string);
	prepare:fn(select: list of string, where: list of Triple):ref Statement;
	step:fn(stmt: ref Statement): list of string;
};
