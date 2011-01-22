Treemap: module
{
	PATH : con "/dis/treemap.dis";

	HORIZONTAL:	con 0;
	VERTICAL:	con 1;
	ASCENDING:	con 0;
	DESCENDING:	con 1;

	TRect: adt
	{	x,y,w,h: real;
		
		distance:	fn(r: self TRect, rr: TRect): real;
		aspect:	fn(r: self TRect): real;
	};

	Item: adt
	{
		size:	real;
		bounds: TRect;
		name: string;
		parent:	cyclic ref Item;
		children:	cyclic list of ref Item;

		enter:	fn(dir: self ref Item, f: ref Item);
		find:		fn(f: self ref Item, name: string): ref Item;
	};

	init:		fn();
	slice:		fn(items: array of ref Item, bounds: TRect, orient: int, order: int);
	square:	fn(items: array of ref Item, bounds: TRect);
	btree:	fn(items: array of ref Item, bounds: TRect, vertical: int);
	strip:		fn(items: array of ref Item, bounds: TRect);
	getitem:	fn(root: ref Item, x, y: real): ref Item;
	getpath:	fn(root: ref Item, x, y: real): list of ref Item;
};
