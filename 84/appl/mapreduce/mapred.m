Mapper : module {
	map: fn(key, value: string, emit: chan of (string, string));
};

Reducer : module {
	reduce: fn(key: string, input: chan of string, emit: chan of string);
};

Reader: module {
	init: fn(mapper: Mapper, emit: chan of (string, string));
	read:fn(file: string, offset: big, nbytes: big);
};
