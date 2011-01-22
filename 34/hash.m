Hash: module{
	PATH: con "/dis/folkfs/hash.dis";
	fun1, fun2: fn(s:string,n:int):int;

	HashVal: type list of int;
	HashNode: adt{
		key:string;
		val: HashVal;  # insert() can update contents
	};
	HashTable: adt{
		a:	array of list of ref HashNode;
		find:	fn(h:self ref HashTable, key:string): HashVal;
		insert:	fn(h:self ref HashTable, key:string, val:HashVal);
		delete:	fn(h:self ref HashTable, key:string);
		all:	fn(h:self ref HashTable): list of ref HashNode;
	};
	new: fn(size:int):ref HashTable;
};

