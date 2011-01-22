Signal: module {
	configstr: string;

	init:	fn(args: list of string);
	config: fn(s: string);
	tickFrame: fn(): array of real;
};
