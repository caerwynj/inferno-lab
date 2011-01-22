implement Synth;

include "sys.m";
sys: Sys;
FD, open, print, sprint, read, tokenize: import sys;

include "draw.m";
Context: import Draw;


module Synth
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

fout: ref FD;

init(nil: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	fout = open("/services/rec-pb/synth", sys->OWRITE);

	for(i := 0; i < 1000; i++) {
		for (j := 0; j < 25; j++) {
			out(j*1000);
		}
		for (j = 25; j > -25; j--) {
			out(j*1000);
		}
		for (j = -25; j < 0; j++) {
			out(j*1000);
		}
	}
};

out(n:int)
{
	b:= array[4] of byte;

	b[0] = b[2] = byte (n & 16rff);
	b[1] = b[3] = byte ((n & 16rff00) >> 8);
	sys->write(fout, b, 4);
};
