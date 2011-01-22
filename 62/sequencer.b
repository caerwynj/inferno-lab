implement Sequencer;

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
include "sequencer.m";

midi2pitch: array of real;

samplerate := 44100.0;
channels := 2;
bps := 2;


modinit()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;
	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	rand = load Rand Rand->PATH;
	audioctl("rate 44100");
	midi2pitch = mkmidi();
}


init(nil: ref Draw->Context, argv: list of string)
{
	sys->pctl(Sys->NEWPGRP, nil);
	modinit();
	argv = tl argv;
	if(len argv != 1)
		return;
	inst := Inst.mk(nil, master);
	linechan := chan of string;
	spawn looper(hd argv, linechan, 0);
	sync := chan of int;
	spawn skiniplay(sync, linechan, inst);
	pid := <-sync;
	<-sync;
	kill(pid, "killgrp");
}

looper(file: string, line: chan of string, loop: int)
{
	io := bufio->open(file, Bufio->OREAD);

	for(;;) {
		while((s := io.gets('\n')) != nil)
			line <-= s;
		if(!loop){
			line <-= nil;
			return;
		}
		io.seek(big 0, Bufio->SEEKSTART);
	}
}

skiniplay(sync: chan of int, linechan: chan of string, inst: ref Inst)
{
	sync <-= sys->pctl(0, nil);
	ob := bufio->open("/dev/audio", Bufio->OWRITE);
	
	rc := chan of array of real;
	out := array[BLOCK*channels] of { * => 0.0};
	while((s := <-linechan) != nil) {
		(n, flds) := sys->tokenize(s, " \n\t\r");
		if(n == 0)
			continue;
		else if((hd flds)[0:2] == "//")
			continue;
		t := real hd tl flds;
		t *= samplerate;
		voice := int hd tl tl flds;
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
		if(voice >= 4 || voice < 0)
			continue;
		inst.ctl <-= (CVOICE, real voice);
		case hd flds {
		"NoteOn" =>
			midi := int hd tl tl tl flds;
			inst.ctl <-= (CKEYON, midi2pitch[midi%len midi2pitch]);
		"NoteOff" =>
			inst.ctl <-= (CKEYOFF, 0.0);
		}
	}
	ob.flush();
	sync <-= 0;
}

play(file: string, ctl: chan of string, inst: ref Inst)
{
	sys->pctl(Sys->NEWPGRP, nil);
	if(sys == nil)
		modinit();
	linechan := chan of string;
	spawn looper(file, linechan, 1);
	skinichan := chan of string;
	sync := chan of int;
	spawn skiniplay(sync, skinichan, inst);
	<-sync;

	for(;;) alt {
	msg := <-ctl =>
		case msg {
		"stop" =>
			kill(sys->pctl(0,nil), "killgrp");
			return;
		}
	s := <-linechan =>
		skinichan <-= s;
	}
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
	inst := array[4] of ref Inst;
	voice := 0;
	mix := Inst.mk(inst, mixer);
	wrc := chan of array of real;
	delay1 := Inst.mk(nil, delay);
	delay1.ctl <-= (CDELAY, 0.005);
	delay1.ctl <-= (CMIX, 0.4);
	delay2 := Inst.mk(nil, delay);
	delay2.ctl <-= (CDELAY, 0.01); 
	delay2.ctl <-= (CMIX, 0.4);
	filt1 := Inst.mk(nil, twopole);
	lfo1 := Inst.mk(nil, lfo);
	lfo1.ctl <-= (CFREQ, 0.7);
	lfo2 := Inst.mk(nil, lfo);
	lfo2.ctl <-= (CFREQ, 0.4);
	lfo2.ctl <-= (CHIGH, 0.2);
	lfo2.ctl <-= (CLOW, 0.1);
	tot := 0;

	for(;;) alt {
	(a, rc ) := <-c =>
		tot += len a;
		if(tot >= BLOCK){
			t := array[1] of real;
			lfo1.c <-= (t, wrc);
			t = <-wrc;
			filt1.ctl <-= (CFREQ, t[0]);
			lfo2.c <-= (t, wrc);
			t =<- wrc;
#			delay2.ctl <-= (CDELAY, t[0]);
			tot -= BLOCK;
		}
		mix.c <-= (a, wrc);
#		filt1.c <-= (<-wrc, wrc);
		delay1.c <-= (<-wrc, wrc);
#		delay2.c <-= (<-wrc, wrc);
		rc <-= <-wrc;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[voice].ctl <-= (m, n);
		CKEYOFF =>
			inst[voice].ctl <-= (m, n);
		CVOICE =>
			voice = int n;
			# two note polyphony for each voice using 'fm' as the generator
			if(inst[voice] == nil)
				inst[voice] = Inst.mk(array[2] of {* => Inst.mk(nil, fm)}, poly);
		}
	}
}

fm(nil: Source, c: Sample, ctl: Control)
{
	waves := array[3] of {* => array[1] of {Inst.mk(nil, waveloop)}};
	vibrato := Inst.mk(nil, waveloop);
	depth := 0.2;
	vibrato.ctl <-= (CFREQ, 2.0);
	ratios := array[3] of {1.0, 0.5, 2.0};
	env := array[3] of ref Inst;
	for(i := 0; i < 3; i++){
		env[i] = Inst.mk(waves[i], adsr);
		env[i].ctl <-= (CATTACK, 0.01);
		env[i].ctl <-= (CDECAY, 0.11);
		env[i].ctl <-= (CSUSTAIN, 0.3);
		env[i].ctl <-= (CRELEASE, 0.001);
	}

	mix := Inst.mk(env, mixer);
	b := array[BLOCK*channels] of real;
	wrc := chan of array of real;
	for(;;) alt{
	(a, rc) := <-c =>
		mix.c <-= (a, wrc);
		a =<- wrc;
		vibrato.c <-= (b[:len a], wrc);
		x :=<- wrc;
		for(i = 0; i < len a; i++)
			a[i] *= (1.0 + x[i] * depth);
		rc <-= a;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			for(i = 0; i < 3; i++) {
				env[i].ctl <-= (m, n);
				waves[i][0].ctl <-= (CFREQ, n * ratios[i]);
			}
		CKEYOFF =>
			for(i = 0; i < 3; i++)
				env[i].ctl <-= (m, n);
		}
	}
}


poly(inst: Source, c: Sample, ctl: Control)
{
	mix := Inst.mk(inst, mixer);
	index := 0;

	for(;;) alt {
	(a, rc ) := <-c =>
		mix.c <-= (a, rc);
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[index].ctl <-= (m, n);
		CKEYOFF =>
			inst[index].ctl <-= (m, n);
			index++;
			index %= len inst;
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
		}
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
