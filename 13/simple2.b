implement Signal;

include "sys.m";
	sys: Sys;
	fprint, fildes, tokenize: import sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;
	Adsr, Waveloop, samplerate, bps, channels,
	Onepole, Noise, Biquad: import dsp;

Simple: adt {
	adsr: ref Adsr;
	filter: ref Onepole;
	noise: ref Noise;
	biquad: ref Biquad;
	loop: ref Waveloop;
	loopGain: real;

	mk: fn(): ref Simple;
	tick: fn(s: self ref Simple): real;
	noteon: fn(s: self ref Simple, freq: real, amplitude: real);
	noteoff: fn(s: self ref Simple, amplitude: real);
};

Simple.mk(): ref Simple
{
	s := ref Simple;
	s.adsr = Adsr.mk(0.01, 0.01, 0.5, 0.01);
	s.loop = Waveloop.mk("/mnt/dsp/raw/impuls10.raw");
	s.filter = Onepole.mk(0.5);
	s.noise = Noise.mk();
	s.biquad = Biquad.mk();
	s.biquad.resonance(440.0, 0.98, 1);
	s.loop.freq(440.0);
	s.loopGain = 0.5;
	return s;
}

Simple.tick(s: self ref Simple): real
{
	lastout := s.loopGain * s.loop.tick();
	lastout += (1.0 - s.loopGain) * s.biquad.tick(s.noise.tick());
	lastout = s.filter.tick(lastout);
	lastout *= s.adsr.tick();
	return lastout;
}

Simple.noteon(s: self ref Simple, freq, amplitude:real )
{
	s.adsr.keyon();
	s.biquad.resonance(freq, 0.98, 1);
	s.loop.freq(freq);
	s.filter.gain = amplitude;
}

Simple.noteoff(s: self ref Simple, nil: real)
{
	s.adsr.keyoff();
}


inst: ref Simple;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();
	inst = Simple.mk();
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
				inst.noteon(freq, amplitude);
			}
		"off" =>
			if(n != 2)
				e = "invalid parms";
			else{
				amplitude := real hd tl flds;
				inst.noteoff(amplitude);
			}
		"ctrl" =>
			;
		}
	}
	configstr = sys->sprint("rate %d\nchans %d\n", 
		int samplerate, channels);
	return e;
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	buf := array[nsamples] of real;
	for(i:=0;i<len buf; i++)
		buf[i] = inst.tick();
	return dsp->norm2raw(buf);
}
