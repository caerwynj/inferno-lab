Cachem: module
{
	PATH: con "/dis/folkfs/cache.dis";
	Cache: adt{
		cache: array of list of ref Btreem->Block;

		create: fn(): ref Cache;
		lookup: fn(c: self ref Cache, id: int): ref Btreem->Block;
		store: fn(c: self ref Cache, b: ref Btreem->Block);
	};
};
