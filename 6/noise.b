implement Signal;

include "sys.m";
	sys: Sys;
include "rand.m";
	rand: Rand;
include "signal.m";
include "dsp.m";
	dsp: Dsp;

samplerate := 22050.0;
seed := 0;
bps := 2;
channels := 1;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	rand = load Rand Rand->PATH;
	rand->init(0);
	config("seed 0");
}

read(n: int): array of byte
{
	samples := n/(bps*channels);
	out :=array[samples] of real;
	for(i:=0;i<samples;i++) {
		out[i] =  real rand->rand(65536);
		out[i] -= 32768.0;
	}
	return dsp->real2pcm(out);
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"seed" =>
		if (n != 2)
			e = "invalid cmd";
		else
			seed = int hd tl flds;
	* =>
		e = "unrecognized cmd";
	}
	configstr = sys->sprint("rate %d\nchans %d\nseed %d\n", int samplerate, channels, seed);
	return e;
}
