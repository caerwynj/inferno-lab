Dsp: module {
	PATH:	con "dsp.dis";

	MAXSAMPLE: con 32768;
	samplerate: real;
	channels: int;
	bps: int;

	Signal: adt {
		ctl: ref Sys->FD;
		data: ref Sys->FD;
		
		open: fn(s: string): ref Signal;
		read: fn(s: self ref Signal, nsamples: int): array of real;
		readbytes: fn(s: self ref Signal, nbyte: int): array of byte;
	};

	init:	fn(libdir: string);
	real2raw: fn(v: array of real): array of byte;
	norm2raw: fn(v: array of real): array of byte;

	Adsr: adt {
		target: real;
		value: real;
		rate: real;
		state: int;
		attack: real;
		decay: real;
		sustain: real;
		release: real;

		tick: fn(s: self ref Adsr): real;
		mk: fn(a, d, s, r: real): ref Adsr;
		keyon: fn(s: self ref Adsr);
		keyoff: fn(s: self ref Adsr);
	};

	Biquad: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Biquad, sample: real): real;
		mk: fn(): ref Biquad;
		resonance: fn(s: self ref Biquad, freq, radius: real, normalize: int);
		notch: fn(s: self ref Biquad, freq: real, radius: real);
	};

	Chorus: adt {

	};

	Delay: adt {
		inputs : array of real;
		lastout: real;
		length: int;
		inpoint: int;
		outpoint: int;

		tick: fn(d: self ref Delay, sample: real): real;
		mk: fn(delay: int, max: int): ref Delay;
	};

	Delayl: adt {
		inputs : array of real;
		lastout: real;
		length: int;
		inpoint: int;
		outpoint: int;
		alpha: real;
		omalpha: real;

		setdelay: fn(d: self ref Delayl, d: real);
		tick: fn(d: self ref Delayl, sample: real): real;
		mk: fn(delay: real, max: int): ref Delayl;
	};

	Delaya: adt {
	};

	Echo: adt {
		delay: ref Delay;
		mix: real;
		lastout: real;

		tick: fn(s: self ref Echo, sample: real): real;
		mk: fn(max: real): ref Echo;
	};

	File: adt {
		io: ref Bufio->Iobuf;
		length: int;
		get:fn(f: self ref File, n: int): real;
		mk: fn(f: string): ref File;
	};

	Filter: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Filter, sample: real): real;
		mk: fn(a, b: array of real): ref Filter;
	};

	Grain: adt {
		escaler: real;
		erate: real;
		attack: int;
		sustain: int;
		decay:	int;
		delay:	int;
		counter:	int;
		pointer:	int;
		start:		int;
		repeats:	int;
		state:	int;

	};

	Granulate: adt {
		raw: ref File;
		data:	array of real;
		delay:	int;
		duration:	int;
		gain:		real;
		grains: array of ref Grain;
		lastoutput:	real;
		noise:	ref Noise;
		offset:	int;
		pointer:	int;
		ramppercent:	int;
		randomfactor:	real;
		randomness:	real;
		stretch:	int;
		stretchcounter:	int;

		mk:fn(file: string): ref Granulate;
		tick:fn(g: self ref Granulate): real;
		setvoices:fn(g: self ref Granulate, n: int);
		calcgrain:fn(g: self ref Granulate, grain: ref Grain);
	};

	Formswep: adt {

	};

	JCRev: adt {

	};

	Jettabl: adt {
		lastout: real;

		tick: fn(j: self ref Jettabl, sample:real): real;
		mk: fn(): ref Jettabl;
	};

	NRev: adt {

	};

	Noise: adt { 
		tick: fn(s: self ref Noise): real;
		mk: fn(): ref Noise;
	};

	Onepole: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Onepole, sample: real): real;
		mk: fn(pole: real): ref Onepole;
		pole: fn(s: self ref Onepole, p: real);
	};

	Onezero: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Onezero, sample: real): real;
		mk: fn(): ref Onezero;
	};

	PRCRev: adt {
		allpassdelays: array of ref Delay;
		combdelays: array of ref Delay;
		combcoef: array of real;
		allpasscoef: real;
		mix: real;
		lastout: array of real;
	
		tick: fn(s: self ref PRCRev, sample: real): real;
		mk: fn(t60: real): ref PRCRev;
	};

	Pitshift: adt {
		delay: array of real;
		delayline: array of ref Delayl;
		mix: real;
		rate: real;
		lastout: real;

		tick: fn(s: self ref Pitshift, sample: real): real;
		mk: fn(): ref Pitshift;
		shift: fn(s: self ref Pitshift, n: real);
	};

	Polezero: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Polezero, sample: real): real;
		mk: fn(): ref Polezero;	
		blockzero: fn(s: self ref Polezero, pole: real);
		allpass: fn(s: self ref Polezero, coeff: real);
	};

	Reedtabl: adt {
		offset :real;
		slope :real;
		lastout: real;

		tick: fn(r: self ref Reedtabl, sample: real): real;
		mk: fn(offset: real, slope: real): ref Reedtabl;
	};
	
	Sphere: adt {
		radius: real;
		mass: real;
		position: ref Vector;
		velocity: ref Vector;

		tick: fn(s: self ref Sphere, inc: real);
		mk: fn(): ref Sphere;
	};

	Subnoise: adt {
		noise: ref Noise;
		rate: int;
		counter: int;
		lastout: real;

		tick: fn(s: self ref Subnoise): real;
		mk: fn(rate: int): ref Subnoise;
	};
	
	Twopole: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Twopole, sample: real): real;
		mk: fn(a, b: array of real): ref Twopole;
		resonance: fn(s: self ref Twopole, freq: real, radius: real, normalize: int);
	};

	Twozero: adt {
		inputs: array of real;
		outputs: array of real;
		a: array of real;
		b: array of real;
		gain: real;

		tick: fn(s: self ref Twozero, sample: real): real;
		mk: fn(a, b: array of real): ref Twozero;
		notch: fn(s: self ref Twozero, freq: real, radius: real);
	};

	Vector: adt{
		x,y,z: real;

		length: fn(s: self ref Vector): real;
		mk: fn(): ref Vector;
	};

	Waveloop: adt {
		data: array of real;
		rate: real;
		time: real;
		lastout: array of real;

		tickframe: fn(s: self ref Waveloop): array of real;
		tick: fn(s: self ref Waveloop): real;
		freq: fn(s: self ref Waveloop, p: real);
		mk: fn(file: string): ref Waveloop;
	};
};
