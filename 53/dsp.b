implement Dsp;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "dsp.m";
include "rand.m";
	rand: Rand;
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt, floor, fabs: import math;

ATTACK, DECAY, SUSTAIN, RELEASE, DONE : con iota;
libdir := "";

init(s: string)
{
	libdir = s;
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;
	rand = load Rand Rand->PATH;
	rand->init(0);
	samplerate = 22050.0;
	channels = 1;
	bps=2;
}

norm2raw(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
		sample := v[i] * 32767.0;
		if(sample> 32767.0)
			sample = 32767.0;
		else if(sample < -32767.0)
			sample = -32767.0;
		b[j++] = byte sample;
		b[j++] = byte (int sample >>8);
	}
	return b;
}

real2raw(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
		sample := v[i];
		if(sample> 32767.0)
			sample = 32767.0;
		else if(sample < -32767.0)
			sample = -32767.0;
		b[j++] = byte sample;
		b[j++] = byte (int sample >>8);
	}
	return b;
}

Signal.open(file: string): ref Signal
{
	sig := ref Signal;
	sig.ctl = sys->open(file + "/clone", Sys->ORDWR);
	if(sig.ctl == nil)
		return nil;
	buf:= array[10] of byte;
	n:= sys->read(sig.ctl, buf, len buf);
	datafile := file + "/" + string buf[:n] + "/data";
	sig.data = sys->open(datafile, Sys->OREAD);
	if(sig.data == nil)
		nil;
	return sig;
}

Signal.read(sig: self ref Signal, nsamples: int): array of real
{
	buf:= array[nsamples*2] of byte;
	b: array of byte;
	out:= array[nsamples] of real;
	nb := sys->read(sig.data, buf, len buf);
	b=buf[0:nb];
	for(i:=0;i<nb/2;i++){
		out[i] = real ((int b[1]<<24 | int b[0] << 16) >> 16);
		b = b[2:];
	}
	return out[0:i];
}

Signal.readbytes(sig: self ref Signal, nbyte: int): array of byte
{
	buf := array[nbyte] of byte;
	nb := sys->read(sig.data, buf, len buf);
	return buf[:nb];
}

Adsr.tick(s: self ref Adsr): real
{
	case (s.state) {
	ATTACK =>
		s.value += s.rate;
		if (s.value >= s.target) {
			s.value = s.target;
			s.rate = s.decay;
			s.target = s.sustain;
			s.state = DECAY;
		}
	DECAY =>
		s.value -= s.decay;
		if (s.value <= s.sustain) {
			s.value = s.sustain;
			s.rate = 0.0;
			s.state = SUSTAIN;
		}
	RELEASE =>
		s.value -= s.release;
		if (s.value <= 0.0) {
			s.value = 0.0;
			s.state = DONE;
		}
	}
	return s.value;
}

Adsr.mk(a, d, s, r: real): ref Adsr
{
	adsr := ref Adsr;
	adsr.target = 1.0;
	adsr.value = 0.0;
	adsr.state = ATTACK;
	adsr.attack = 1.0 / (a * samplerate);
	adsr.decay = 1.0 / (d * samplerate);
	adsr.sustain = s;
	adsr.release = s / (r * samplerate);
	adsr.rate = adsr.attack;
	return adsr;
}

Adsr.keyon(s: self ref Adsr)
{
	s.target = 1.0;
	s.rate = s.attack;
	s.state = ATTACK;
}

Adsr.keyoff(s: self ref Adsr)
{
	s.target = 0.0;
	s.rate = s.release;
	s.state = RELEASE;
}

Biquad.mk(): ref Biquad
{
	f := ref Biquad;
	f.gain = 1.0;
	f.a = array[] of {1.0, 0.0, 0.0};
	f.b = array[] of {1.0, 0.0, 0.0};
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Biquad.tick(s: self ref Biquad, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[0] * s.inputs[0] + s.b[1] * s.inputs[1] + s.b[2] * s.inputs[2];
	s.outputs[0] -= s.a[2] * s.outputs[2] + s.a[1] * s.outputs[1];
	s.inputs[2] = s.inputs[1];
	s.inputs[1] = s.inputs[0];
	s.outputs[2] = s.outputs[1];
	s.outputs[1] = s.outputs[0];
	return s.outputs[0];
}

Biquad.resonance(s: self ref Biquad, freq, radius: real, normalize: int)
{
	s.a[2] = radius * radius;
	s.a[1] = -2.0 * radius * cos(2.0 * Pi * freq / samplerate);
	if(normalize){
		s.b[0] = 0.5 - 0.5 * s.a[2];
		s.b[1] = 0.0;
		s.b[2] = -s.b[0];
	}
}

Biquad.notch(s: self ref Biquad, freq: real, radius: real)
{
	s.b[2] = radius * radius;
	s.b[1] = -2.0 * radius * cos(2.0 * Pi * freq / samplerate);
}

Delay.tick(r: self ref Delay, sample: real): real
{
	r.inputs[r.inpoint++] = sample;
	r.inpoint %= r.length;
	r.lastout = r.inputs[r.outpoint++];
	r.outpoint %= r.length;
	return r.lastout;
}

Delay.mk(delay: int, max: int): ref Delay
{
	d := ref Delay;
	d.lastout = 0.0;
	d.length = max  + 1;
	d.inputs = array[d.length] of {* => 0.0};
	if(delay >= d.length){
		d.outpoint = d.inpoint + 1;
	} else if (delay < 0) {
		d.outpoint = d.inpoint;
	} else {
		d.outpoint = d.inpoint - delay;
	}
	while(d.outpoint < 0)
		d.outpoint += d.length;
	d.outpoint %= len d.inputs;
	return d;
}

Delayl.tick(s: self ref Delayl, sample: real): real
{
	s.inputs[s.inpoint++] = sample;
	s.inpoint %= len s.inputs;
	s.lastout = s.inputs[s.outpoint] * s.omalpha;
	if(s.outpoint+1 < len s.inputs)
		s.lastout += s.inputs[s.outpoint+1] * s.alpha;
	else
		s.lastout += s.inputs[0] * s.alpha;
	s.outpoint++;
	s.outpoint %= len s.inputs;
	return s.lastout;
}

Delayl.setdelay(s: self ref Delayl, d: real)
{
	outpointer: real;
	if(d >= real len s.inputs){
		outpointer = real s.inpoint + 1.0;
	}else if(d < 0.0){
		outpointer = real s.inpoint;
	}else{
		outpointer = real s.inpoint - d;
	}
	while(outpointer < 0.0)
		outpointer += real len s.inputs;
	s.outpoint = int outpointer;
	s.outpoint %= len s.inputs;
	s.alpha = outpointer - real s.outpoint;
	s.omalpha = 1.0 - s.alpha;
}

Delayl.mk(delay: real, max: int): ref Delayl
{
	d := ref Delayl;
	d.inputs = array[max] of {* => 0.0};
	d.inpoint = 0;
	d.outpoint = 0;
	d.lastout = 0.0;
	d.setdelay(delay);
	return d;
}

Echo.mk(max: real): ref Echo
{
	e := ref Echo;
	length := int(max + 2.0);
	e.delay = Delay.mk(length>>1, length);
	e.mix = 0.5;
	e.lastout = 0.0;
	return e;
}

Echo.tick(s: self ref Echo, sample: real): real
{
	s.lastout = s.mix * s.delay.tick(sample);
	s.lastout += sample * (1.0 - s.mix);
	return s.lastout;
}

File.mk(file: string): ref File
{
	f := ref File(nil, 0);
	(n, d) := sys->stat(libdir + file);
	if(n<0)
		return nil;
	f.io = bufio->open(file, Bufio->OREAD);
	f.length = int d.length / 2;
	return f;
}

NORM : con 1.0/32767.0;
File.get(f: self ref File, n: int): real
{
	f.io.seek(big (n * 2), Bufio->SEEKSTART);
	b := array[2] of int;
	b[0] = f.io.getb();
	b[1] = f.io.getb();
	sample := (b[1] <<24 | b[0] << 16) >> 16;
	return real sample * NORM;
}

Filter.mk(a, b: array of real): ref Filter
{
	f := ref Filter;
	f.gain = 1.0;
	f.a = a;
	f.b = b;
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Filter.tick(s: self ref Filter, sample: real): real
{
	i: int;
	s.outputs[0] = 0.0;
	s.inputs[0] = s.gain * sample;
	for (i=len s.b-1; i>0; i--) {
		s.outputs[0] += s.b[i] * s.inputs[i];
		s.inputs[i] = s.inputs[i-1];
	}
	s.outputs[0] += s.b[0] * s.inputs[0];

	for (i=len s.a-1; i>0; i--) {
		s.outputs[0] += -s.a[i] * s.outputs[i];
		s.outputs[i] = s.outputs[i-1];
	}

	return s.outputs[0];
}

blankgranulate: Granulate;
blankgrain: Grain;
Granulate.mk(f: string): ref Granulate
{
	g := ref blankgranulate;
	g.duration = 30;
	g.ramppercent = 50;
	g.randomfactor = 0.1;
	g.gain = 1.0;
	g.noise = Noise.mk();
	g.raw = File.mk(f);
	if(g.raw == nil){
		sys->fprint(sys->fildes(2), "error opening %s\n", f);
		return nil;
	}
#	g.data = readfile(f);
#	normalize(g.data, 1.0);
	g.setvoices(1);
	return g;
}

GSTOPPED, GFADEIN, GSUSTAIN, GFADEOUT: con iota;

Granulate.setvoices(g: self ref Granulate, n: int)
{
	oldsize := len g.grains;
	g.grains = (array[n] of ref Grain)[0:] = g.grains;
	for(i := oldsize; i < n; i++){
		g.grains[i] = ref blankgrain;
		g.grains[i].repeats = 0;
		count := int (real i * real g.duration * 0.001 * samplerate / real n);
		g.grains[i].counter = count;
		g.grains[i].state = GSTOPPED;
	}
	g.gain = 1.0 / real len g.grains;
}

Granulate.calcgrain(g: self ref Granulate, grain: ref Grain)
{
	if(grain.repeats > 0){
		grain.repeats--;
		grain.pointer = grain.start;
		if(grain.attack > 0){
			grain.escaler = 0.0;
			grain.erate = -grain.erate;
			grain.counter = grain.attack;
			grain.state = GFADEIN;
		}else{
			grain.counter = grain.sustain;
			grain.state = GSUSTAIN;
		}
		return;
	}

	seconds := real g.duration * 0.001;
	seconds += (seconds * g.randomfactor * g.noise.tick());
	count := int (seconds * samplerate);
	grain.attack = int (real g.ramppercent * 0.005 * real count);
	grain.decay = grain.attack;
	grain.sustain = count - 2 * grain.attack;
	grain.escaler = 0.0;
	if(grain.attack > 0){
		grain.erate = 1.0 / real grain.attack;
		grain.counter = grain.attack;
		grain.state = GFADEIN;
	}else{
		grain.counter = grain.sustain;
		grain.state = GSUSTAIN;
	}
	
	seconds = real g.delay * 0.001;
	seconds += (seconds * g.randomfactor * g.noise.tick());
	count = int (seconds * samplerate);
	grain.delay = count;

	grain.repeats = g.stretch;

	seconds = real g.offset * 0.001;
	seconds += (seconds * g.randomfactor * g.noise.tick());
	offset := int (seconds * samplerate);
	grain.pointer = g.pointer + offset;
	while(grain.pointer >= g.raw.length)
		grain.pointer -= g.raw.length;
	if(grain.pointer < 0)
		grain.pointer = 0;
	grain.start = grain.pointer;
}

Granulate.tick(g: self ref Granulate): real
{
	g.lastoutput = 0.0;
	if(g.raw.length == 0)
		return g.lastoutput;
	
	sample: real;
	grains := g.grains;
	for(i := 0; i < len grains; i++){
		if(grains[i].counter == 0){
			case grains[i].state {
			GSTOPPED =>
				g.calcgrain(grains[i]);
			GFADEIN =>
				if(grains[i].sustain > 0){
					grains[i].counter = grains[i].sustain;
					grains[i].state = GSUSTAIN;
				}else if(grains[i].decay > 0){
					grains[i].counter = grains[i].decay;
					grains[i].erate = -grains[i].erate;
					grains[i].state = GFADEOUT;
				}else if(grains[i].delay > 0){
					grains[i].counter = grains[i].delay;
					grains[i].state = GSTOPPED;
				}else{
					g.calcgrain(grains[i]);
				}
			GSUSTAIN =>
				if(grains[i].decay > 0){
					grains[i].counter = grains[i].decay;
					grains[i].erate = -grains[i].erate;
					grains[i].state = GFADEOUT;
				}else if(grains[i].delay > 0){
					grains[i].counter = grains[i].delay;
					grains[i].state = GSTOPPED;
				}else
					g.calcgrain(grains[i]);

			GFADEOUT =>
				if(grains[i].delay > 0){
					grains[i].counter = grains[i].delay;
					grains[i].state = GSTOPPED;
				}else
					g.calcgrain(grains[i]);
			}

		}
		if(grains[i].state > 0){
			sample = g.raw.get(grains[i].pointer++);
			if(grains[i].state == GFADEIN || grains[i].state == GFADEOUT){
				sample *= grains[i].escaler;
				grains[i].escaler += grains[i].erate;
			}
			g.lastoutput += sample;
			
			if(grains[i].pointer >= g.raw.length)
				grains[i].pointer = 0;
		}
		grains[i].counter--;
	}
	if(g.stretchcounter++ == g.stretch){
		g.pointer++;
		if(g.pointer >= g.raw.length)
			g.pointer = 0;
		g.stretchcounter = 0;
	}
	return g.lastoutput * g.gain;
}


Jettabl.mk(): ref Jettabl
{
	j := ref Jettabl;
	j.lastout = 0.0;
	return j;
}

Jettabl.tick(j: self ref Jettabl, r: real): real
{
	# perform "tabl lookup" using a polynomial
	# calculation (x^3 - x), which approximates
	# the jet sigmoid behavior.
	n := r * (r * r - 1.0);
	if(n > 1.0)
		n = 1.0;
	if(n < -1.0)
		n = -1.0;
	j.lastout = n;
	return n;
}

Noise.mk(): ref Noise
{
	return ref Noise;
}

Noise.tick(nil: self ref Noise): real
{
	MAX := 65536;
	n := 2.0 * real rand->rand(MAX) / real(MAX + 1);
	n -= 1.0;
	return n;
}

Onepole.mk(pole: real): ref Onepole
{
	f := ref Onepole;
	f.gain = 1.0;
	f.a = array[] of {1.0, -0.9};
	f.b = array[] of {0.1};
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	f.pole(pole);
	return f;
}

Onepole.tick(s: self ref Onepole, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[0] * s.inputs[0] - s.a[1] * s.outputs[1];
	s.outputs[1] = s.outputs[0];
	return s.outputs[0];
}

Onepole.pole(s: self ref Onepole, p: real)
{
	if(p > 0.0)
		s.b[0] = 1.0 - p;
	else
		s.b[0] = 1.0 + p;
	s.a[1] = - p;
}

Onezero.mk(): ref Onezero
{
	f := ref Onezero;
	f.gain = 1.0;
	f.a = array[] of {1.0};
	f.b = array[] of {0.5, 0.5};
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Onezero.tick(s: self ref Onezero, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[1] * s.inputs[1] + s.b[0] * s.inputs[0];
	s.inputs[1] = s.inputs[0];
	return s.outputs[0];
}

Polezero.mk(): ref Polezero
{
	f := ref Polezero;
	f.gain = 1.0;
	f.a = array[] of {1.0, 0.0};
	f.b = array[] of {1.0, 0.0};
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Polezero.tick(s: self ref Polezero, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[0] * s.inputs[0] + s.b[1] * s.inputs[1] - s.a[1] * s.outputs[1];
	s.inputs[1] = s.inputs[0];
	s.outputs[1] = s.outputs[0];
	return s.outputs[0];
}

Polezero.blockzero(s: self ref Polezero, pole:real)
{
	s.b[0] = 1.0;
	s.b[1] = -1.0;
	s.a[0] = 1.0;
	s.a[1] = -pole;
}

Polezero.allpass(s: self ref Polezero, coeff: real)
{
	s.b[0] = coeff;
	s.b[1] = 1.0;
	s.a[0] = 1.0;
	s.a[1] = coeff;
}

PRCRev.mk(T60: real): ref PRCRev
{
	p := ref PRCRev;
	p.allpassdelays = array[4] of ref Delay;
	p.combdelays = array[4] of ref Delay;
	p.combcoef = array[4] of real;
	p.lastout = array[2] of real;
	lengths := array[] of {353, 1097, 1777, 2137};
	scaler := samplerate / 44100.0;
	delay, i: int;
	if(scaler != 1.0){
		for(i = 0; i< 4; i++) {
			delay = int(floor(scaler * real lengths[i]));
			if((delay & 1) == 0)
				delay++;
			while(!isprime(delay))
				delay += 2;
			lengths[i] = delay;
		}
	}
	for(i = 0; i<2; i++){
		p.allpassdelays[i] = Delay.mk(lengths[i], lengths[i]);
		p.combdelays[i] = Delay.mk(lengths[i+2], lengths[i+2]);
		p.combcoef[i] = pow(10.0, (-3.0 * real lengths[i+2] / (T60 * samplerate)));
	}
	p.allpasscoef = 0.7;
	p.mix = 0.5;
	return p;
}

PRCRev.tick(s: self ref PRCRev, input: real): real
{
	temp, temp0, temp1, temp2, temp3: real;

	temp = s.allpassdelays[0].lastout;
	temp0 = s.allpasscoef * temp;
	temp0 += input;
	s.allpassdelays[0].tick(temp0);
	temp0 = -(s.allpasscoef * temp0) + temp;
		
	temp = s.allpassdelays[1].lastout;
	temp1 = s.allpasscoef * temp;
	temp1 += temp0;
	s.allpassdelays[1].tick(temp1);
	temp1 = -(s.allpasscoef * temp1) + temp;
		
	temp2 = temp1 + (s.combcoef[0] * s.combdelays[0].lastout);
	temp3 = temp1 + (s.combcoef[1] * s.combdelays[1].lastout);

	s.lastout[0] = s.mix * (s.combdelays[0].tick(temp2));
	s.lastout[1] = s.mix * (s.combdelays[1].tick(temp3));
	temp = (1.0 - s.mix) * input;
	s.lastout[0] += temp;
	s.lastout[1] += temp;
		
	return (s.lastout[0] + s.lastout[1]) *	0.5;

}

Pitshift.mk(): ref Pitshift
{
	p := ref Pitshift;
	p.delay = array[2] of {12.0, 412.0};
	p.delayline = array[2] of {Delayl.mk(12.0, 1024), Delayl.mk(512.0, 1024)};
	p.mix = 0.5;
	p.rate = 1.0;
	return p;
}

Pitshift.tick(s: self ref Pitshift, input: real): real
{
	env := array[2] of real;
	s.delay[0] = s.delay[0] + s.rate;
	while (s.delay[0] > 1012.0) 
		s.delay[0] -= 1000.0;
	while (s.delay[0] < 12.0) 
		s.delay[0] += 1000.0;
	s.delay[1] = s.delay[0] + 500.0;
	while (s.delay[1] > 1012.0) 
		s.delay[1] -= 1000.0;
	while (s.delay[1] < 12.0) 
		s.delay[1] += 1000.0;
	s.delayline[0].setdelay(s.delay[0]);
	s.delayline[1].setdelay(s.delay[1]);
	env[1] = fabs(s.delay[0] - 512.0) * 0.002;
	env[0] = 1.0 - env[1];
	s.lastout =	env[0] * s.delayline[0].tick(input);
	s.lastout += env[1] * s.delayline[1].tick(input);
	s.lastout *= s.mix;
	s.lastout += (1.0 - s.mix) * input;
	return s.lastout;
}

Pitshift.shift(s: self ref Pitshift, n: real)
{
	if (n < 1.0){
		s.rate = 1.0 - n; 
	}
	else if (n > 1.0){
		s.rate = 1.0 - n;
	}
	else {
		s.rate = 0.0;
		s.delay[0] = 512.0;
	}
}

Subnoise.tick(s: self ref Subnoise): real
{
	if(++s.counter > s.rate){
		s.lastout = s.noise.tick();
		s.counter = 1;
	}
	return s.lastout;
}

Subnoise.mk(rate: int): ref Subnoise
{
	s := ref Subnoise(Noise.mk(), rate, rate, 0.0);
	return s;
}

Waveloop.mk(file: string): ref Waveloop
{
	w := ref Waveloop;
	w.data = readfile(file);
	if(w.data == nil){
		sys->fprint(sys->fildes(2), "couldn't read file\n");
		w.data = array[2] of {* => 0.0};
	}
	normalize(w.data, 1.0);
	w.lastout = array[channels] of {* => 0.0};
	w.rate = 1.0;
	w.time = 0.0;
	return w;
}

Waveloop.tickframe(s: self ref Waveloop): array of real
{
	index : int;
	alpha : real;

	while(s.time < 0.0)
		s.time += real len s.data;
	while(s.time >= real len s.data)
		s.time -= real len s.data;
	index = int s.time;
	alpha = s.time - real index;
	index *= channels;
	for(i:=0; i<channels; i++){
		s.lastout[i] = s.data[index%(len s.data)];
		s.lastout[i] += (alpha * (s.data[(index+channels)%(len s.data)] - s.lastout[i]));
		index++;
	}
	s.time += s.rate;
	return s.lastout;
}

Waveloop.tick(s: self ref Waveloop): real
{
	out := 0.0;
	s.tickframe();
	if(channels == 1)
		return s.lastout[0];
	for(i := 0; i < channels; i++)
		out += s.lastout[i];
	return out / real channels;

}

Waveloop.freq(s: self ref Waveloop, p: real)
{
	s.rate = real(len s.data) * p / samplerate;
}

readfile(file: string): array of real
{
	n := 0;
	y := array[8] of real;
	io := bufio->open(libdir + file, bufio->OREAD);
	if(io == nil)
		return nil;
	for(;;){
	 	(b, eof) := getw(io);
		if(eof)
			break;
		if(n >= len y)
			y = (array[len y * 2] of real)[0:] = y;
		y[n++] = real b;
	}
	return y[0:n];
}

normalize(y: array of real, peak: real)
{
	max := 0.0;
	for(i := 0; i < len y; i++)
		if(fabs(y[i]) > max)
			max = fabs(y[i]);
	if(max > 0.0){
		max = 1.0 / max;
		max *= peak;
		for(i = 0; i < len y; i++)
			y[i] *= max;
	}
}

swab := 0;
getw(io: ref Iobuf): (int, int)
{
	b:= array[2] of int;
	for(i:=0;i<2;i++){
		b[i] = io.getb();
		if(b[i] == bufio->EOF)
			return (0, 1);
	}
	if(swab)
		n := b[1]<<24 | b[0] << 16;
	else 
		n = b[0]<<24 | b[1] << 16;
	return (n >> 16, 0);
}

Reedtabl.mk(offset: real, slope: real): ref Reedtabl
{
	r := ref Reedtabl(offset, slope, 0.0);
	return r;
}

Reedtabl.tick(r: self ref Reedtabl, n: real): real
{
	r.lastout = r.offset + (r.slope * n);
	if(r.lastout > 1.0)
		r.lastout = 1.0;
	if(r.lastout < -1.0)
		r.lastout = -1.0;
	return r.lastout;
}

Sphere.mk(): ref Sphere
{
	s := ref Sphere;
	s.position = Vector.mk();
	s.velocity = Vector.mk();
	return s;
}

Sphere.tick(s: self ref Sphere, inc: real)
{
	s.position.x = s.position.x + inc * s.velocity.x;
	s.position.y = s.position.y + inc * s.velocity.y;
	s.position.z = s.position.z + inc * s.velocity.z;
}

Twopole.mk(a, b: array of real): ref Twopole
{
	f := ref Twopole;
	f.gain = 1.0;
	f.a = a;
	f.b = b;
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Twopole.tick(s: self ref Twopole, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[0] * s.inputs[0] - s.a[2] * s.outputs[2] - s.a[1] * s.outputs[1];
	s.outputs[2] = s.outputs[1];
	s.outputs[1] = s.outputs[0];
	return s.outputs[0];
}

Twopole.resonance(s: self ref Twopole, freq: real, radius: real, normalize: int)
{
	re, im: real;
	s.a[2] = radius * radius;
	s.a[1] = -2.0 * radius * cos(2.0*Pi * freq / samplerate);
	if(normalize){
		re = 1.0 - radius + (s.a[2] - radius) * cos(2.0 * Pi * freq / samplerate);
		im = (s.a[2] - radius) * sin(2.0*Pi*freq/samplerate);
		s.b[0] = sqrt(pow(re,2.0) + pow(im, 2.0));
	}
}

Twozero.mk(a, b: array of real): ref Twozero
{
	f := ref Twozero;
	f.gain = 1.0;
	f.a = a;
	f.b = b;
	f.inputs = array[len f.b] of {* => 0.0};
	f.outputs = array[len f.a] of {* => 0.0};
	if (f.a[0] != 1.0) {
		for (i:=0; i<len f.b; i++)
			f.b[i] /= f.a[0];
		for (i=0; i<len f.a; i++)
			f.a[i] /= f.a[0];
	}
	return f;
}

Twozero.tick(s: self ref Twozero, sample: real): real
{
	s.inputs[0] = s.gain * sample;
	s.outputs[0] = s.b[2] * s.inputs[2]  + s.b[1] * s.inputs[1] + s.b[0] * s.inputs[0];
	s.inputs[2] = s.inputs[1];
	s.inputs[1] = s.inputs[0];
	return s.outputs[0];
}

Twozero.notch(s: self ref Twozero, freq: real, radius: real)
{
	s.b[2] = radius * radius;
	s.b[1] = -2.0 * radius * cos(2.0 * Pi * freq / samplerate);
	if(s.b[1] > 0.0)
		s.b[0] = 1.0 / (1.0 + s.b[1] + s.b[2]);
	else
		s.b[0] = 1.0 / (1.0 - s.b[1] + s.b[2]);
	s.b[1] *= s.b[0];
	s.b[2] *= s.b[0];
}

Vector.length(s: self ref Vector): real
{
	t := s.x * s.x;
	t += s.y * s.y;
	t += s.z * s.z;
	t = sqrt(t);
	return t;
}

Vector.mk(): ref Vector
{
	return ref Vector;
}

isprime(number: int): int
{
	if (number == 2)
		return 1;
	if (number & 1)	{
		for (i:=3; i<int(sqrt(real number))+1; i+=2)
			if ( (number % i) == 0) 
			return 0;
		return 1; 
	}
	else 	
		return 0; 
}
