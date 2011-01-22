Dsp: module {
	PATH:	con "/n/j/Inferno/usr/caerwyn/limbo/signalfs/dsp.dis";

	Sig: adt {
		ctl: ref Sys->FD;
		data: ref Sys->FD;
		
		open: fn(s: string): ref Sig;
		read: fn(s: self ref Sig, nsamples: int): array of real;
		readbytes: fn(s: self ref Sig, nbyte: int): array of byte;
	};

	init:	fn();
	real2pcm: fn(v: array of real): array of byte;
};
