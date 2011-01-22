implement Signal;

include "sys.m";
	sys: Sys;
include "rand.m";
	rand: Rand;
include "signal.m";

samplerate := 22050.0;
seed := 0;
bps := 2;
channels := 1;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	rand = load Rand Rand->PATH;
	rand->init(0);
	config("seed 0");
}

# next sample for n channels
tickFrame(): array of real
{
	out :=array[channels] of real;
	for(i:=0;i<channels;i++) {
		out[i] = real rand->rand(65536);
		out[i] -= 32768.0;
	}
	return out;
}

config(s: string)
{
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"seed" =>
		seed = int hd tl flds;
	}
	configstr = sys->sprint("rate %d\nchans %d\nseed %d\n", int samplerate, channels, seed);
}
