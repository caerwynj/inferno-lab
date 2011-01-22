implement Signal;

include "sys.m";
	sys: Sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;

ATTACK, DECAY, SUSTAIN, RELEASE, DONE : con iota;
samplerate := 22050.0;
seed := 0;
bps := 2;
channels := 1;
target := 0.0;
value := 0.0;
rate := 0.001;
state := ATTACK;
attack := 0.001;
decay := 0.001;
sustain := 0.5;
release := 0.01;

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
		out[i] =  tick() * 32767.0;
	return dsp->real2pcm(out);
}

tick(): real 
{
	case (state) {
	ATTACK =>
		value += rate;
		if (value >= target) {
			value = target;
			rate = decay;
			target = sustain;
			state = DECAY;
		}
	DECAY =>
		value -= decay;
		if (value <= sustain) {
			value = sustain;
			rate = 0.0;
			state = SUSTAIN;
		}
	RELEASE =>
		value -= release;
		if (value <= 0.0) {
			value = 0.0;
			state = DONE;
		}
	}
	return value;
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"keyon" =>
		target = 1.0;
		rate = attack;
		state = ATTACK;
	"keyoff" =>
		target = 0.0;
		rate = release;
		state = RELEASE;
	"attack" =>
		attack = real hd tl flds;
	"decay" =>
		decay = real hd tl flds;
	"sustain" =>
		sustain = real hd tl flds;
	"release" =>
		release = real hd tl flds;
	"rate" =>
		rate = real hd tl flds;
	"attacktime" =>
		time := real hd tl flds;
		attack = 1.0 / (time * samplerate);
	"decaytime" =>
		time := real hd tl flds;
		decay = 1.0 / (time * samplerate);
	"releasetime" =>
		time := real hd tl flds;
		release = sustain / (time * samplerate);
	"target" =>
		target = real hd tl flds;
		if(value < target) {
			state = ATTACK;
			sustain = target;
			rate = attack;
		} else if(value > target) {
			state = DECAY;
			sustain = target;
			rate = decay;
		}
	"value" =>
		state = SUSTAIN;
		target = real hd tl flds;
		value = target;
		sustain = value;
		rate = 0.0;
	}
	configstr = sys->sprint("rate %g\nchans %d\ntarget %g\nvalue %g\n", 
		samplerate, channels, target, value);
	configstr += sys->sprint("attack %g\ndecay %g\nsustain %g\nrelease %g\n",
		attack, decay, sustain, release);
		
	return e;
}
