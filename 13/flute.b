implement Signal;

include "sys.m";
	sys: Sys;
include "dsp.m";
	dsp: Dsp;
	samplerate, channels, bps, Delayl, Jettabl, Onepole, 
	Polezero, Noise, Adsr, Waveloop: import dsp;
include "signal.m";

Flute: adt {
	boreDelay: ref Delayl;
	jetDelay: ref Delayl;
	jetTabl: ref Jettabl;
	filter: ref Onepole;
	dcBlock: ref Polezero;
	noise: ref Noise;
	adsr: ref Adsr;
	vibrato: ref Waveloop;

	length: int;
	endReflection: real;
	jetReflection: real;
	noiseGain: real;
	vibratoGain: real;
	outputGain: real;
	jetRatio: real;
	maxPressure: real;
	lastFrequency: real;
	lastOutput: real;

	mk: fn(lowestfreq: real): ref Flute;
	tick: fn(s: self ref Flute): real;
	noteon: fn(s: self ref Flute, freq: real, amplitude: real);
	noteoff: fn(s: self ref Flute, amplitude: real);
	setFrequency: fn(s: self ref Flute, frequency: real);
};

Flute.mk(lowestfreq: real): ref Flute
{
	f := ref Flute;

	f.length = int(samplerate /  lowestfreq + 1.0);
	f.boreDelay = Delayl.mk(100.0, f.length);
	f.length >>=1;
	f.jetDelay = Delayl.mk(49.9, f.length);
	f.jetTabl = Jettabl.mk();
	f.filter = Onepole.mk(0.9);
	f.dcBlock = Polezero.mk();
	f.dcBlock.blockzero(0.99);
	f.noise = Noise.mk();
	f.adsr = Adsr.mk(0.005, 0.01, 0.8, 0.010);
	f.vibrato = Waveloop.mk("/mnt/dsp/raw/sinewave.raw");
	f.vibrato.freq(5.925);
	f.filter.pole(0.7 - 0.1 * 22050.0 / samplerate);
	f.filter.gain = -1.0;
	f.endReflection = 0.5;
	f.jetReflection = 0.5;
	f.noiseGain = 0.15;
	f.vibratoGain = 0.05;
	f.jetRatio = 0.32;
	f.maxPressure = 0.0;
	f.lastFrequency = 220.0;
	f.outputGain = 0.0;
	return f;
}

Flute.tick(s: self ref Flute): real
{
	pressureDiff: real;
	breathPressure: real;

	# Calculate the breath pressure (envelope + noise + vibrato)
	breathPressure = s.maxPressure * s.adsr.tick();
	breathPressure += breathPressure * s.noiseGain * s.noise.tick();
	breathPressure += breathPressure * s.vibratoGain * s.vibrato.tick();

	temp := s.filter.tick( s.boreDelay.lastout );
	temp = s.dcBlock.tick(temp); # Block DC on reflection.

	pressureDiff = breathPressure - (s.jetReflection * temp);
	pressureDiff = s.jetDelay.tick(pressureDiff);
	pressureDiff = s.jetTabl.tick(pressureDiff) + (s.endReflection * temp);
	s.lastOutput = 0.3 * s.boreDelay.tick(pressureDiff);

	s.lastOutput *= s.outputGain;
	return s.lastOutput;
}

Flute.setFrequency(s: self ref Flute, frequency: real)
{
	s.lastFrequency = frequency;
	if (frequency <= 0.0 ) {
		s.lastFrequency = 220.0;
	}
	# We're overblowing here.
	s.lastFrequency *= 0.66666;
	# Delay = length - approximate filter delay.
	delay := samplerate / s.lastFrequency -  2.0;
	if (delay <= 0.0) 
		delay = 0.3;
	else if (delay > real s.length) 
		delay = real s.length;

	s.boreDelay.setdelay(delay);
	s.jetDelay.setdelay(delay * s.jetRatio);
}

Flute.noteon(s: self ref Flute, freq: real, amplitude: real)
{
	s.setFrequency(freq);
	s.adsr.attack =  amplitude * 0.02;
	s.maxPressure = (1.1 + (amplitude * 0.20)) / 0.8;
	s.adsr.keyon();
	s.outputGain = amplitude + 0.001;
}

Flute.noteoff(s: self ref Flute, amplitude: real)
{
	s.adsr.release = amplitude * 0.02;
	s.adsr.keyoff();
}

flute: ref Flute;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();
	flute = Flute.mk(10.0);
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
				flute.noteon(freq, amplitude);
			}
		"off" =>
			if(n != 2)
				e = "invalid parms";
			else{
				amplitude := real hd tl flds;
				flute.noteoff(amplitude);
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
		buf[i] = flute.tick() * 0.2;
	return dsp->norm2raw(buf);
}

