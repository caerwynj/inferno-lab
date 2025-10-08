Turtle: module {
	PATH: con "/dis/lib/turtle.dis";
	Triple : adt {
		s, p, o: string;
	};

	init: fn();
	read: fn(file: string): list of ref Triple;
};
