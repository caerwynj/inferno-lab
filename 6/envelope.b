implement Signal;

include "sys.m";
	sys: Sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;

samplerate := 22050.0;
seed := 0;
bps := 2;
channels := 1;
target := 0.0;
value := 0.0;
rate := 0.001;
state := 0;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	config("target 0");
}

read(n: int): array of byte
{
	samples := n/(bps*channels);
	out :=array[samples] of real;
	for(i:=0;i<samples;i++)
		out[i] =  tick();
	return dsp->real2pcm(out);
}

tick(): real 
{
	if (state) {
		if (target > value) {
			value += rate;
			if (value >= target) {
				value = target;
				state = 0;
			}
		}else {
			value -= rate;
			if (value <= target) {
				value = target;
				state = 0;
			}
		}
	}
	return value;
}

# next sample for n channels
tickFrame(): array of real
{
	out :=array[channels] of real;
	for(i:=0;i<channels;i++) {
		out[i] = tick();
	}
	return out;
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"keyon" =>
		target = 1.0;
		if(value != target)
			state = 1;
	"keyoff" =>
		target = 0.0;
		if(value != target)
			state = 1;
	"rate" =>
		rate = real hd tl flds;
	"time" =>
		time := real hd tl flds;
		rate = 1.0 / (time * samplerate);
	"target" =>
		target = real hd tl flds;
		if(value != target)
			state = 1;
	"value" =>
		state = 0;
		target = real hd tl flds;
		value = target;
	}
	configstr = sys->sprint("rate %g\nchans %d\ntarget %g\nvalue %g\n", 
		rate, channels, target, value);
	return e;
}
