implement Signal;

include "sys.m";
	sys: Sys;
	fprint: import sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;
	Sig: import dsp;

samplerate := 22050.0;
bps := 2;
channels := 1;
gain := 1.0;
inputs: array of real;
outputs: array of real;
wave: ref Sig;
filename:= "";
length := 4096;
inPoint := 0;
outPoint := 0;
delay := 0;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();

	inputs = array[length] of {* => 0.0};
	outputs = array[1] of {* => 0.0};
	config("");
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	out := wave.read(nsamples);
	for(i:=0;i<len out;i++)
		out[i] = tick(out[i]);
	return dsp->real2pcm(out);
}

tick(sample: real): real
{
	inputs[inPoint++] = sample;
	inPoint %= length;
	outputs[0] = inputs[outPoint++];
	outPoint %= length;
	return outputs[0];
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	if(n > 0){
		case hd flds {
		"gain" =>
			if(n != 2)
				return "invalid parms";
			gain = real hd tl flds;
		"delay " =>
			if(n != 2)
				return "invalid parms";
			d := int hd tl flds;
			if(d >= length){
				outPoint = inPoint + 1;
				delay = length - 1;
			} else if (d < 0) {
				outPoint = inPoint;
				delay = 0;
			} else {
				outPoint = inPoint - d;
				delay = d;
			}
			while(outPoint < 0)
				outPoint += length;
		"source" =>
			if(n != 2)
				return "invalid parms";
			filename = hd tl flds;
			wave = Sig.open(filename);
			if(wave == nil)
				e = "invalid source";
		* =>
			fprint(wave.ctl, "%s", s);
		}
	}
	configstr = sys->sprint("rate %d\nchans %d\ngain %g\nsource %s\n", 
		int samplerate, channels, gain, filename);
	return e;
}

energy(): real
{
	i: int;
	e := 0.0;
	if (inPoint >= outPoint) {
		for (i=outPoint; i<inPoint; i++) {
			t := inputs[i];
			e += t*t;
		}
	} else {
		for (i=outPoint; i<length; i++) {
			t := inputs[i];
			e += t*t;
		}
		for (i=0; i<inPoint; i++) {
			t := inputs[i];
			e += t*t;
		}
	}
	return e;
}
