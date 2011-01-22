implement Signal;

include "sys.m";
	sys: Sys;
	fprint, fildes, tokenize: import sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;
	Adsr, Waveloop, samplerate, bps, channels: import dsp;

adsr: ref Adsr;
wave: ref Waveloop;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();
	adsr = Adsr.mk(0.001, 0.001, 0.5, 0.01);
	wave = Waveloop.mk("/mnt/dsp/raw/sinewave.raw");
	config("");
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	if(n > 0){
		case hd flds {
		"on" =>
			if(n != 3)
				e = "invalid parms";
			else {
				freq := real hd tl flds;
				amplitude := real hd tl tl flds;
				wave.freq(freq);
				adsr.keyon();
			}
		"off" =>
			if(n != 2)
				e = "invalid parms";
			else{
				amplitude := real hd tl flds;
				adsr.keyoff();
			}
		"ctrl" =>
			;
		}
	}
	configstr = sys->sprint("rate %g\nchans %d\n", 
		samplerate, channels);
	return e;
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	buf := array[nsamples] of real;
	b: array of real;
	b = buf[0:];
	for(i:=0; i<nsamples; i+=channels){
		b[0:] = wave.tickframe();
		b = b[channels:];
	}
	for(i=0; i<nsamples; i++)
		buf[i] *= adsr.tick();
	return dsp->norm2raw(buf);
}
