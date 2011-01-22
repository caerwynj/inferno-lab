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

midi2pitch:= array[129] of {
8.18,8.66,9.18,9.72,10.30,10.91,11.56,12.25,
12.98,13.75,14.57,15.43,16.35,17.32,18.35,19.45,
20.60,21.83,23.12,24.50,25.96,27.50,29.14,30.87,
32.70,34.65,36.71,38.89,41.20,43.65,46.25,49.00,
51.91,55.00,58.27,61.74,65.41,69.30,73.42,77.78,
82.41,87.31,92.50,98.00,103.83,110.00,116.54,123.47,
130.81,138.59,146.83,155.56,164.81,174.61,185.00,196.00,
207.65,220.00,233.08,246.94,261.63,277.18,293.66,311.13,
329.63,349.23,369.99,392.00,415.30,440.00,466.16,493.88,
523.25,554.37,587.33,622.25,659.26,698.46,739.99,783.99,
830.61,880.00,932.33,987.77,1046.50,1108.73,1174.66,1244.51,
1318.51,1396.91,1479.98,1567.98,1661.22,1760.00,1864.66,1975.53,
2093.00,2217.46,2349.32,2489.02,2637.02,2793.83,2959.96,3135.96,
3322.44,3520.00,3729.31,3951.07,4186.01,4434.92,4698.64,4978.03,
5274.04,5587.65,5919.91,6271.93,6644.88,7040.00,7458.62,7902.13,
8372.02,8869.84,9397.27,9956.06,10548.08,11175.30,11839.82,12543.85,
13289.75};

samplerate := 44100.0;
channels := 2;
bps := 2;

Sequencer: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	math = load Math Math->PATH;
	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	stderr = fildes(2);
	argv = tl argv;
	audioctl("rate 44100");
	inst := array[4] of ref Inst;
	io := bufio->fopen(fildes(0), Bufio->OREAD);
	ob := bufio->fopen(fildes(1), Bufio->OWRITE);
	sys->pctl(Sys->NEWPGRP, nil);
	nvoice := 0.0;
	rc := chan of array of real;
	mixerc := chan of (array of real, chan of array of real);
	spawn mixer(inst, mixerc, nil);
	delayi := Inst.mk(delay);
	while((s := io.gets('\n')) != nil) {
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
			while(nsamples > big 0){
				block := 16384;
				if(big block > nsamples)
					block = int nsamples;
				out := array[block*channels] of {0.0};
				mixerc <-= (out, rc);
#				delayi.c <-= (<-rc, rc);
				b := norm2raw(<-rc);
				ob.write(b, len b);
				nsamples -= big block;
			}
		}
		if(voice >= len inst || voice < 0)
			continue;
		if(inst[voice] == nil){
			inst[voice] = Inst.mk(instrument);
			nvoice++;
		}
		case hd flds {
		"NoteOn" =>
			midi := int hd tl tl tl flds;
			inst[voice].ctl <-= (CKEYON, midi2pitch[midi%len midi2pitch]);
		"NoteOff" =>
			inst[voice].ctl <-= (CKEYOFF, 0.0);
		}
	}
	ob.flush();
	kill(sys->pctl(0, nil), "killgrp");
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

Inst: adt {
	c: chan of (array of real, chan of array of real);
	ctl: chan of (int, real);
	gain: real;

	mk: fn(f: ref fn(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))): ref Inst;
};

Inst.mk(f: ref fn(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))): ref Inst
{
	this := ref Inst;
	this.c = chan of (array of real, chan of array of real);
	this.ctl = chan of (int, real);
	this.gain = 0.1;
	spawn f(this.c, this.ctl);
	return this;

}

# Control messages
CFREQ, CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN, CRELEASE, CDELAY: con iota;

instrument(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))
{
	adsri := Inst.mk(adsr);
	adsri.ctl <-= (CATTACK, 0.01);
	adsri.ctl <-= (CDECAY, 0.11);
	adsri.ctl <-= (CSUSTAIN, 0.3);
	adsri.ctl <-= (CRELEASE, 0.001);

	wave := Inst.mk(waveloop);

	for(;;) alt{
	(a, rc) := <-c =>
		wrc := chan of array of real;
		wave.c <-= (a, wrc);
		adsri.c <-= (<-wrc, rc);
	(m, n) := <-ctl =>
		case m {
		CFREQ =>
			wave.ctl <-= (m, n);
		CKEYON =>
			wave.ctl <-= (CFREQ, n);
			adsri.ctl <-= (m, n);
		CKEYOFF =>
			adsri.ctl <-= (m, n);
		}
	}
}


waveloop(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))
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

adsr(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))
{
	state:= ATTACK;
	target := 1.0;
	value := 0.0;
	attack := 1.0;
	decay := 1.0;
	sustain := 0.1;
	release := 0.1;
	rate := attack;

	for(;;) alt{
	(a, rc) := <-c =>
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


mixer(inst: array of ref Inst, c: chan of (array of real, chan of array of real), nil: chan of (int, real))
{

	for(;;) alt {
	(a, rc) := <-c =>
		b := array[len inst] of array of real;
		for(i := 0; i < len inst; i++)
			b[i] = array[len a] of { * => 0.0};
		wrc := chan of array of real;
		for(i = 0; i < len inst; i++) {
			if(inst[i] != nil){
				inst[i].c <-= (b[i], wrc);
				b[i] =<- wrc;
			}
		}
		for(i = 0; i < len a; i++){
			a[i] = 0.0;
			for(j := 0; j < len inst; j++)
				a[i] += b[j][i] * 0.1;
		}
		rc <-= a;
	}
}


delay(c: chan of (array of real, chan of array of real), ctl: chan of (int, real))
{
	lastout := 0.0;
	delay := 0.3;   # in seconds
	inpoint := 0;
	outpoint := int (delay * samplerate * real channels);
	inputs := array[outpoint * 2] of { * => 0.0};
	mix := 0.3;
	echo := 0.0;

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
			outpoint = int (n * samplerate * real channels);
			inputs = array[outpoint * 2] of { * => 0.0};
		}
	}
}


# generate basic waves

LENGTH: con 256;
halfwave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH/2; i++)
		b[i] = math->sin(real i * 2.0 * Math->Pi / real LENGTH);
	return b;
}

sinewave(): array of real
{
	b := array[LENGTH] of { * => 0.0};
	for(i := 0; i < LENGTH; i++)
		b[i] = math->sin(real i * 2.0 * Math->Pi / real LENGTH);
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
