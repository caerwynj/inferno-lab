Ffs: module {
	configstr: string;

	init:	fn(args: list of string);
	config: fn(s: string): string;
	read: fn(n: int): array of byte;
};
