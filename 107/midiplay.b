implement Midiplay;

include "sys.m";
	sys: Sys;
	fprint, fildes, sprint, print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
	sin, cos, Pi, pow, sqrt: import math;
include "rand.m";
	rand: Rand;
include "midiplay.m";
include "midi.m";
	midi: Midi;
	Header, Track, Event: import midi;


midi2pitch: array of real;

samplerate := 8000.0;
channels := 1;
bps := 2;

#For MIDI
tpb : real;
bpm := 120;
tickrate :real;

dbg := 0;

modinit()
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	midi = load Midi Midi->PATH;
	midi->init();
	math = load Math Math->PATH;
	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	rand = load Rand Rand->PATH;
	audioctl(sys->sprint("rate %d", int samplerate));
	audioctl(sys->sprint("chans %d", channels));
	midi2pitch = mkmidi();
}


init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);
	modinit();
	argv = tl argv;
	if(len argv != 1) {
		sys->fprint(sys->fildes(2), "usage: midiplay file.mid\n");
		exit;
	}
	inst := Inst.mk(nil, master);
	sync := chan of int;
	spawn midiplay(sync, hd argv, inst);
	pid := <-sync;
	<-sync;
	kill(pid, "killgrp");
}

interleave(hdr: ref Header): list of  Skini
{
	skini: list of Skini;
	for(;;){
		min := 100000;
		for(i:=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events > 0 && hdr.tracks[i].events[0].delta < min)
				min = hdr.tracks[i].events[0].delta;
		}
		if(min == 100000)
			break;
		l : list of ref Event;
		for(i=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events > 0){
				if(hdr.tracks[i].events[0].delta <= min){
					l = hdr.tracks[i].events[0] :: l;
					hdr.tracks[i].events = hdr.tracks[i].events[1:];
				}else{
					hdr.tracks[i].events[0].delta -= min;
				}
			}
		}
		first := 1;
		for(; l != nil; l = tl l){
			e :=hd l;
			if(first){
				s := outevent(e);
				if (s != nil) {
					skini = *s :: skini;
					first = 0;
				}
			}else{
				e.delta = 0;
				s := outevent(e);
				if (s != nil)
					skini = *s :: skini;
			}
		}
	}
	return reverse(skini);
}

reverse(l: list of Skini): list of Skini
{
	t: list of Skini;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

Skini: adt {
	ev: string;
	realtime: real;
	channel: int;
	param1: int;
	param2: int;
};

outevent(m: ref Event):  ref Skini
{
	s: ref Skini;

	pick e := m {
	Control =>
		case e.etype {
			Midi->NOTEON =>
				realtime := real e.delta /  tickrate;
				ev := "NoteOn";
				if(e.param2 == 0)
					ev = "NoteOff";
				s =  ref Skini(ev, realtime, e.mchannel, e.param1, e.param2);
			Midi->NOTEOFF =>
				realtime := real e.delta / tickrate;
				s =  ref Skini("NoteOff", realtime, e.mchannel, e.param1, 0);
		}
	Sysex =>
		fprint(fildes(2), "sysex\n");
	Meta =>
		if(e.etype == Midi->TEMPO){
			n := 0;
			for(k:=0; k < len e.data; k++)
				n = (n<<8)| int e.data[k];
			bpm = 60000000 / n;
			tickrate =  (real bpm/  60.0) * tpb;
			if(dbg)print("TEMPO %d, bpm %d, tickrate %f\n", n, 60000000 / n, tickrate);
		}
#		else	fprint(fildes(2), "meta %s\n", string e.data);
	}
	return s;
}

midiplay(sync: chan of int, file: string, inst: ref Inst)
{
	sync <-= sys->pctl(0, nil);
	ob := bufio->open("/dev/audio", Bufio->OWRITE);
	
	if(ob == nil) {
		sys->fprint(sys->fildes(2), "failed opening audio\n");
		sync <-= 0;
		raise "error /dev/audio";
	}

	hdr := midi->read(file);
	if(hdr == nil) {
		sys->fprint(sys->fildes(2), "failed opening audio\n");
		sync <-= 0;
		raise "error file.mid";
	}
	tpb = real hdr.tpb;
	tickrate =  (real bpm/  60.0) * tpb;
	skini := interleave(hdr);
	if(dbg)
		print("got list of %d\n", len skini);
	
	rc := chan of array of real;
	out := array[BLOCK*channels] of { * => 0.0};
	if(dbg)print("midiplay\n");
	for(l := skini; l != nil; l = tl l) {
		s := hd l;
#		print("%s\t%f\t%d\t%d\t%d\n", s.ev, s.realtime,  s.channel, s.param1, s.param2);
		t := s.realtime;
		t *= samplerate;
		voice := s.channel;
		if(t > 0.0){
			nsamples := big t & 16rFFFFFFFE;
			block := BLOCK;
			while(nsamples > big 0){
				if(big block > nsamples)
					block = int nsamples;
				inst.c <-= (out[:block*channels], rc);
				b := norm2raw(<-rc);
				ob.write(b, len b);
				nsamples -= big block;
			}
		}
		if(voice >= 16 || voice < 0)
			continue;
		inst.ctl <-= (CVOICE, real voice);
		case s.ev {
		"NoteOn" =>
			mid := s.param1;
			inst.ctl <-= (CKEYON, midi2pitch[mid%len midi2pitch]);
		"NoteOff" =>
			mid := s.param1;
			inst.ctl <-= (CKEYOFF, midi2pitch[mid%len midi2pitch]);
		}
	}
	ob.flush();
	sync <-= 0;
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}

audioctl(s: string): int
{
	fd := sys->open("#A/audioctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", s) < 0)
		return -1;
	return 0;
}


Inst.mk(insts: Source, f: Instrument): ref Inst
{
	this := ref Inst;
	this.c = chan of (array of real, chan of array of real);
	this.ctl = chan of (int, real);
	spawn f(insts, this.c, this.ctl);
	return this;
}

master(nil: Source, c: Sample, ctl: Control)
{
	inst := Inst.mk(array[16] of {* => Inst.mk(nil, fm)}, poly);  # one channel, 16 note polyphony
	wrc := chan of array of real;
	delay1 := Inst.mk(nil, delay);
	delay1.ctl <-= (CDELAY, 0.18);
	delay1.ctl <-= (CMIX, 0.09);
	delay2 := Inst.mk(nil, delay);
	delay2.ctl <-= (CDELAY, 0.4); 
	delay2.ctl <-= (CMIX, 0.05);
	filt1 := Inst.mk(nil, onepole);
	filt1.ctl <-= (CPOLE, 0.2);
	lfo1 := Inst.mk(nil, lfo);
	lfo1.ctl <-= (CFREQ, 0.7);
	lfo2 := Inst.mk(nil, lfo);
	lfo2.ctl <-= (CFREQ, 0.4);
	lfo2.ctl <-= (CHIGH, 0.2);
	lfo2.ctl <-= (CLOW, 0.1);

	for(;;) alt {
	(a, rc ) := <-c =>
		inst.c <-= (a, wrc);
		filt1.c <-= (<-wrc, wrc);
		delay1.c <-= (<-wrc, wrc);
		delay2.c <-= (<-wrc, wrc);
		rc <-= <-wrc;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst.ctl <-= (m, n);
		CKEYOFF =>
			inst.ctl <-= (m, n);
		}
	}
}

fm(nil: Source, c: Sample, ctl: Control)
{
	waves := array[3] of {* =>  Inst.mk(nil, waveloop)};
	vibrato := Inst.mk(nil, waveloop);
	depth := 0.1;
	vibrato.ctl <-= (CFREQ, 10.0);
	ratios := array[3] of {1.0, 0.5, 2.0};
	mix := array[1] of { * =>  Inst.mk(waves, mixer)};
	env := Inst.mk(mix, adsr);
	env.ctl <-= (CATTACK, 0.01);
	env.ctl <-= (CDECAY, 0.11);
	env.ctl <-= (CSUSTAIN, 0.3);
	env.ctl <-= (CRELEASE, 0.001);
	b := array[BLOCK*channels] of real;
	wrc := chan of array of real;
	for(;;) alt{
	(a, rc) := <-c =>
		env.c <-= (a, wrc);
		a =<- wrc;
		vibrato.c <-= (b[:len a], wrc);
		x :=<- wrc;
		for(i := 0; i < len a; i++)
			a[i] *= (1.0 + x[i] * depth);
		rc <-= a;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			env.ctl <-= (m, n);
			for(i := 0; i < 3; i++) {
				waves[i].ctl <-= (CFREQ, n * ratios[i]);
			}
		CKEYOFF =>
			env.ctl <-= (m, n);
		}
	}
}


poly(inst: Source, c: Sample, ctl: Control)
{
	mix := Inst.mk(inst, mixer);
	index := 0;
	npoly := len inst;
	pitch := array[npoly] of real;

	for(;;) alt {
	(a, rc ) := <-c =>
		mix.c <-= (a, rc);
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[index].ctl <-= (m, n);
			pitch[index] = n;
			index++;
			index %= npoly;
		CKEYOFF =>
			for(j := 0; j < npoly; j++){
				if(pitch[j] == n){
					inst[j].ctl <-= (m, n);
				}
			}
		}
	}
}

instrument(nil: Source, c: Sample, ctl: Control)
{
	wave := array[1] of {Inst.mk(nil, waveloop)};

	adsri := Inst.mk(wave, adsr);
	adsri.ctl <-= (CATTACK, 0.01);
	adsri.ctl <-= (CDECAY, 0.11);
	adsri.ctl <-= (CSUSTAIN, 0.3);
	adsri.ctl <-= (CRELEASE, 0.001);


	for(;;) alt{
	(a, rc) := <-c =>
		adsri.c <-= (a, rc);
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			adsri.ctl <-= (m, n);
			wave[0].ctl <-= (CFREQ, n);
		CKEYOFF =>
			adsri.ctl <-= (m, n);
		}
	}
}

waveloop(nil: Source, c: Sample, ctl: Control)
{
	data: array of real;
	rate := 1.0;
	time := 0.0;
	index := 0;
	alpha : real;

	data = sinewave();

	for(;;) alt {
	(a, rc) := <-c =>
		n := len data;
		for(i := 0; i < len a; i += channels){
			while(time < 0.0)
				time += real n;
			while(time >= real n)
				time -= real n;
			index = int time;
			alpha = time - real index;
			index *= channels;
			for(j := 0; j < channels && i < len a; j++){
				a[i+j] = data[index%n];
				a[i+j] += (alpha * (data[(index+channels)%n] - a[i+j]));
				index++;
			}
			time += rate;
		}
		rc <-= a;
	(m, n) := <-ctl =>
		if(m == CFREQ){
			rate = (real len data * n) / samplerate;
			time = 0.0;
			index = 0;
		}
	}
}

ATTACK, DECAY, RELEASE, SUSTAIN, DONE: con iota;

adsr(inst: Source, c: Sample, ctl: Control)
{
	state:= DONE;
	target := 1.0;
	value := 0.0;
	attack := 1.0;
	decay := 1.0;
	sustain := 0.1;
	release := 0.1;
	rate := attack;

	wrc := chan of array of real;
	for(;;) alt{
	(a, rc) := <-c =>
		if(inst[0] == nil)
			continue;
		if(state != DONE){
			inst[0].c <-= (a, wrc);
			a =<- wrc;
		} else if(state == DONE){
			rc <-= nil;
			continue;
		}
		# XXX if state = DONE don't bother processing any data
		for(i := 0; i < len a; i += channels){
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
			for(j := 0; j < channels && i < len a; j++)
				a[i+j] *= value;
		}
		rc <-= a;
	(m, r) := <-ctl =>
		case (m) {
		CKEYON =>
			value = 0.0;
			target = 1.0;
			rate = attack;
			state = ATTACK;
		CKEYOFF =>
			target = 0.0;
			rate = release;
			state = RELEASE;
		CATTACK =>
			attack = 1.0 / (r * samplerate);
		CDECAY =>
			decay = 1.0 / (r * samplerate);
		CSUSTAIN =>
			sustain = r;
		CRELEASE =>
			release = sustain / (r * samplerate);
		}
	}
}

mixer(inst: Source, c: Sample, nil: Control)
{

	t := array[len inst] of array of real;
	b := array[len inst] of array of real;
	for(i := 0; i < len inst; i++)
		b[i] = array[BLOCK * channels] of { * => 0.0};

	for(;;) alt {
	(a, rc) := <-c =>
		wrc := chan of array of real;
		for(i = 0; i < len inst; i++)
			if(inst[i] != nil)
				inst[i].c <-= (b[i][0:len a], wrc);
# concurrency!
# they may not come back in the same order we sent them
		j := 0;
		for(i = 0; i < len inst; i++)
			if(inst[i] != nil)
				t[j++] =<- wrc; 
		for(i = 0; i < len a; i++){
			a[i] = 0.0;
			for(k := 0; k < j; k++)
				if(t[k] != nil)
					a[i] += t[k][i] * 0.5;
		}
		rc <-= a;
	}
}

delay(nil: Source, c: Sample, ctl: Control)
{
	inputs := array[int (2.0 * samplerate * real channels)] of { * => 0.0};
	lastout := 0.0;
	delay := 0.0;   # in seconds
	inpoint := 0;
	outpoint := inpoint - int (delay * samplerate * real channels);
	mix := 0.5;
	echo := 0.0;

	while(outpoint < 0)
		outpoint += len inputs;
	outpoint %= len inputs;

	for(;;) alt {
	(a, rc) := <-c =>
		for(i := 0; i < len a; i++){
			inputs[inpoint++] = a[i];
			inpoint %= len inputs;
			lastout = inputs[outpoint++];
			outpoint %= len inputs;
			echo = lastout * mix;
			echo += a[i] * (1.0 - mix);
			a[i] = echo;
		}
		rc <-= a;
	(m, n) := <-ctl =>
		case (m) {
		CDELAY =>
			outpoint =  inpoint - int (n * samplerate * real channels);
			while(outpoint < 0)
				outpoint += len inputs;
			outpoint %= len inputs;
		CMIX =>
			mix = n;
		}
	}
}


# some elementary filters
# http://ccrma.stanford.edu/~jos/filters/filters.html


# y(n) = b₀x(n) + b₁x(n-1)
onezero(nil: Source, c: Sample, ctl: Control)
{
	last := array[channels] of {* => 0.0};
	b := array[2] of {1.0, 1.0};
	x := array[BLOCK * channels] of real;

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] + b[1] * last[j];
			for(i := channels+j; i < len y; i += channels)
				y[i] = b[0] * x[i] + b[1] * x[i-channels];
		}
		last[0:] = x[len y - channels:];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		CZERO =>
			if(n > 0.0)
				b[0] = 1.0 / (1.0 + n);
			else
				b[0] = 1.0 / (1.0 - n);
			b[1] = -n * b[0];
		}
	}
}

# y(n) = b₀x(n) - a₁y(n-1)
onepole(nil: Source, c: Sample, ctl: Control)
{
	lastout := array[channels] of {* => 0.0};
	b := array[1] of {0.4};		#gain
	a := array[2] of {1.0, -0.9};

	for(;;) alt {
	(x, rc) := <-c =>
		for(j := 0; j < channels; j++){
			x[j] = b[0] * x[j] - a[1] * lastout[j];
			for(i := channels+j; i < len x; i += channels)
				x[i] = b[0] * x[i] - a[1] * x[i-channels];
		}
		lastout[0:] = x[len x-channels:];
		rc <-= x;
	(m, n) := <-ctl =>
		case m {
		CPOLE =>
			a[1] = -n;
			if(n > 0.0)
				b[0] = 1.0 - n;
			else
				b[0] = 1.0 + n;
		}
	}
}

# y(n) = b₀x(n) - a₁y(n-1) - a₂y(n-1)
twopole(nil: Source, c: Sample, ctl: Control)
{
	lastout := array[channels*2] of {* => 0.0};
	b := array[1] of {0.005};		#gain
	a := array[3] of {1.0, 0.0, 0.0};
	radius := 0.99;
	freq := 500.0;
	a[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
	a[2] = radius**2;
	x := array[BLOCK * channels] of real;

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] - a[1] * lastout[channels+j] - a[2] * lastout[j];
			y[j + channels] = b[0] * x[j + channels] - a[1] * y[j] - a[2] * lastout[channels + j];
			for(i := channels*2+j; i < len y; i += channels)
				y[i] = b[0] * x[i]  - a[1] * y[i-channels] - a[2] * y[i-channels*2];
		}
		lastout[0:] = y[len y - 2*channels:];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		CFREQ =>
			freq = n;
		CRADIUS =>
			radius = n;
		}
		a[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
		a[2] = radius * radius;
#normalize
		re := 1.0 - radius + (a[2] - radius) * cos(2.0 * Pi * 2.0 * freq / samplerate);
		im := (a[2] - radius) * sin(2.0 * Pi * freq/samplerate);
		b[0] = sqrt(pow(re, 2.0) + pow(im, 2.0));
	}
}


# y(n) = b₀x(n) + b₁x(n-1) + b₂x(n-1)
twozero(nil: Source, c: Sample, ctl: Control)
{
	b := array [3] of {2.0, 0.0, 0.0};
	radius := 0.99;
	freq := samplerate / 4.0;
	b[2] = radius * radius;
	b[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
	x := array[BLOCK * channels] of real;
	last := array[2*channels] of {* => 0.0};

	for(;;) alt {
	(y, rc) := <-c =>
		x[0:] = y;
		for(j := 0; j < channels; j++){
			y[j] = b[0] * x[j] + b[1] * last[channels+j] + b[2] * last[j];
			y[j + channels] = b[0] * x[channels+j] + b[1] * x[j] + b[2] * last[channels+j];
			for(i := channels*2 + j; i < len y; i += channels)
				y[i] = b[0] * x[i] + b[1] * x[i-channels] + b[2] * x[i-channels*2];
		}
		last[0:] = x[len y - 2*channels:len y];
		rc <-= y;
	(m, n) := <-ctl =>
		case m {
		CFREQ =>
			freq = n;
		CRADIUS =>
			radius = n;
		}
		b[2] = radius * radius;
		b[1] = -2.0 * radius * cos(2.0 * Pi * freq/samplerate);
		if(b[1] > 0.0)
			b[0] = 1.0 / (1.0 + b[1] + b[2]);
		else
			b[0] = 1.0 / (1.0 - b[1] + b[2]);
		b[1] *= b[0];
		b[2] *= b[0];
	}
}

# y(n) = b₀x(n) + b₁x(n-1) + b₂x(n-1) - a₁y(n-1) - a₂y(n-2)
# biquad - resonance filter

# lfo's don't need a high sampling rate and only need one channel
# parameters change only one blocking factor which limits the
# sampling rate.
lfo(nil: Source, c: Sample, ctl: Control)
{
	high := 800.0;
	low := 10.0;
	range := (high - low)/2.0;
	rate := 1.0;
	time := 0.0;
	index := 0;
	alpha : real;
	T := samplerate / real BLOCK;

	data := sinewave();

	for(;;) alt {
	(a, rc) := <-c =>
		n := len data;
		for(i := 0; i < len a; i++){
			while(time < 0.0)
				time += real n;
			while(time >= real n)
				time -= real n;
			index = int time;
			alpha = time - real index;
			a[i] = data[index%n];
			a[i] += (alpha * (data[(index+1)%n] - a[i]));
			a[i] =  a[i] * range + range + low;
			time += rate;
		}
		rc <-= a;
	(m, n) := <-ctl =>
		case m{
		CFREQ =>
			if(n < (T/2.0)){
				rate = (real len data * n) / T;
				time = 0.0;
				index = 0;
			}
		CHIGH =>
			high = n;
			range = (high - low)/2.0;
		CLOW =>
			low = n;
			range = (high - low)/2.0;
		}
	}
}

# generate basic waves

LENGTH: con 256;
halfwave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH/2; i++)
		b[i] = sin(real i * 2.0 * Pi / real LENGTH);
	return b;
}

sinewave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH; i++)
		b[i] = sin(real i * 2.0 * Pi / real LENGTH);
	return b;
}

sineblnk(): array of real
{
	b := sinewave();
	for(i := 0; i < LENGTH/2; i++)
		b[i] = b[2*i];
	for(i = LENGTH/2; i < LENGTH; i++)
		b[i] = 0.0;
	return b;
}

fwavblnk(): array of real
{
	b := sineblnk();
	for(i:=0;i<LENGTH/4;i++)
		b[i+LENGTH/4] = b[i];
	return b;
}

impuls(n: int): array of real
{
	b := array[LENGTH] of real;
	for(i := 0; i < LENGTH; i++){
		t := 0.0;
		for(j := 1; j <= n; j++)
			t += cos(real i * real j * 2.0 * Math->Pi / real LENGTH);
		b[i] = t * real n;
	}
	return b;
}

noise(): array of real
{
	b := array[LENGTH] of real;
	MAX := 65536;
	for(i := 0; i < LENGTH; i++)
		b[i] = 2.0 * real rand->rand(MAX) / real(MAX + 1);
	return b;
}

# generic utils

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

mkmidi(): array of real
{
	a := array[128] of real;
	for(i:=0;i < len a; i++)
		a[i] = 220.0 * math->pow(2.0, (real i-57.0)/12.0);
	return a;
}
