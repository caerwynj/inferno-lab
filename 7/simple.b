implement Signal;

include "sys.m";
	sys: Sys;
	fprint, fildes, tokenize: import sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;
	Sig: import dsp;

# basic instrument using sinewave
samplerate := 22050.0;
pitch := 440.0;
channels := 1;
bps:=2;
rate:=1.0;


adsr: ref Sig;
wave: ref Sig;

# we can't open other modules here that are part
# of signalfs, because signal calls this init fn in
# it's main thread.
init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();
	adsr = Sig.open("/mnt/dsp/adsr");
	if(adsr == nil)
		fprint(fildes(2),  "could not open adsr\n");
	wave = Sig.open("/mnt/dsp/wave");
	if(wave == nil)
		fprint(fildes(2), "could not open wave\n");
	fprint(wave.ctl, "file /mnt/dsp/raw/sinewave.raw");
	config("");
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	if(n > 0){
		case hd flds {
		"on" =>
			if(n != 2)
				e = "invalid parms";
			else {
				freq := real hd tl flds;
				fprint(wave.ctl, "pitch %g", freq);
				fprint(adsr.ctl, "keyon");
			}
		"off" =>
			fprint(adsr.ctl, "keyoff");
		"ctrl" =>
			;
		"file" =>
			if(n != 2)
				e = "invalid parms";
			else
				fprint(wave.ctl, "file %s", hd tl flds);
		}
	}
	configstr = sys->sprint("rate %d\nchans %d\n", 
		int samplerate, channels);
	return e;
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	buf := wave.read(nsamples);
	env := adsr.read(nsamples);
	for(i:=0;i<len buf; i++)
		if(env[i] == 0.0)
			buf[i] = 0.0;
		else
			buf[i] *= (env[i] / 32767.0);
	return dsp->real2pcm(buf);
}
