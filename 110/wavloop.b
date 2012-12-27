implement WavPlay;

include "sys.m";
include "draw.m";

sys:	Sys;
FD:	import sys;

stderr:	ref FD;
inf:	ref FD;
prog:	string;
buff4:	array of byte;
data:	con "/dev/audio";
ctl:	con "/dev/audioctl";
buffz:	con Sys->ATOMICIO;

dbg := 1;
FINDZERO := 1;
NLOOPS := 10;
S2B := 1;

Wave: adt {
	data: array of byte;
	fmt: Fmt;
	cuepoints: array of Cue;
	loops: array of Loop;
};

Fmt: adt{
	format: int;
	chans: int;
	rate: int;
	bits: int;
	nbytes: int;
};

Cue: adt {
	id: int;
	chunkstart: int;
	blockstart: int;
	sampleoffset: int;
};

Loop: adt {
	id: int;
	looptype: int;
	start:int;
	end: int;
	fraction: int;
	playcount: int;
};

WaveBuf: adt{
	wave: Wave;
	nloop: int;
	pos: int;		
	state: int;
	get: fn(b: self ref WaveBuf, n: int, a: array of byte): int;
};
START, LOOPING, RELEASING, RELEASE, DONE: con iota;

WavPlay: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

ioerror()
{
	sys->fprint(stderr, "%s: read error: %r\n", prog);
	exit;
}

shortfile(diag: string)
{
	sys->fprint(stderr, "%s: short read: %s\n", prog, diag);
	exit;
}

error(s: string)
{
	sys->fprint(stderr, "%s: bad wave file: %s\n", prog, s);
	exit;
}

get(c: int, s: string)
{
	n := sys->read(inf, buff4, c);
	if (n < 0)
		ioerror();
	if (n != c)
		shortfile("expected " + s);
}

gets(c: int, s: string) : string
{
	get(c, s);
	return string buff4[0:c];
}

need(s: string)
{
	get(4, s);
	if (string buff4 != s) {
		sys->fprint(stderr, "%s: not a wave file\n", prog);
		exit;
	}
}

getl(s: string) : int
{
	get(4, s);
	return int buff4[0] + (int buff4[1] << 8) + (int buff4[2] << 16) + (int buff4[3] << 24);
}

getw(s: string) : int
{
	get(2, s);
	return int buff4[0] + (int buff4[1] << 8);
}

skip(n: int)
{
	b := array[1] of byte;
	while (n > 0) {
		sys->read(inf, b, 1);
		n--;
	}
}

getcue(l: int): (int, array of Cue)
{
	cues: array of Cue;
	ncue := getl("Num Cue Points");
	
	cues = array[ncue] of Cue;
	for (i := 0; i < ncue; i++){
		id := getl("Cue ID");
		getl("Position");
		getl("RIFF ID");
		chunkstart := getl("Chunk start");
		blockstart := getl("Block start");
		sampleoffset := getl("Sample offset");
		cues[i] = Cue(id, chunkstart, blockstart, sampleoffset);
	}
	
	return (0, cues);
}

getfmt(l: int) : (int, Fmt)
{
	fmt := Fmt(0, 0, 0, 0, 0);
	
	fmt.format = getw("format");
	fmt.chans= getw("channels");
	fmt.rate = getl("rate");
	getl("AvgBytesPerSec");
	getw("BlockAlign");
	fmt.bits = getw("bits");
	fmt.nbytes = fmt.chans*(fmt.bits/8);
	l -= 16;
	return (l, fmt);
}

getsmpl(l: int) : (int, array of Loop)
{
	loops : array of Loop;
	
	getl("Manufacturer");
	getl("Product");
	getl("Sample Period");
	getl("MIDI Unity Note");
	getl("MIDI Pitch Fraction");
	getl("SMPTE Format");
	getl("SMPTE Offset");
	nloops := getl("Num loops");
	getl("Sampler Data");
	loops = array[nloops] of Loop;
	for (i := 0; i < nloops; i++) {
		id := getl("Cue point ID");
		looptype := getl("loop type");
		start := getl("start");
		end := getl("end");
		fraction := getl("fraction");
		playcount := getl("playcount");
		loops[i] = Loop(id, looptype, start, end, fraction, playcount);
	}
	return (0, loops);
}

getdata(l: int): (int, array of byte)
{
	sample := array[l] of byte;
	n := sys->read(inf, sample, l);
	if (n < 0)
		ioerror();
	if (n != l)
		shortfile("expected sample data");
	return (0, sample);
}

init(nil: ref Draw->Context, argv: list of string)
{
	l: int;
	a: string;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	prog = hd argv;
	argv = tl argv;
	while (argv != nil && (hd argv)[0] == '-'){
		case hd argv {
		"-n" =>
			FINDZERO = 0;
		"-l" =>
			NLOOPS = int hd argv;
			argv = tl argv;
		"-s" =>
			S2B = 0;
		}
		argv = tl argv;
	}
	if (argv == nil) {
		inf = sys->fildes(0);
		if (inf == nil) {
			sys->fprint(stderr, "%s: could not fopen stdin: %r\n", prog);
			exit;
		}
	}
	else if (tl argv != nil) {
		sys->fprint(stderr, "usage: %s [infile]\n", prog);
		exit;
	}
	else {
		inf = sys->open(hd argv, Sys->OREAD);
		if (inf == nil) {
			sys->fprint(stderr, "%s: could not open %s: %r\n", prog, hd argv);
			exit;
		}
	}
	cf := sys->open(ctl, Sys->OWRITE);
	if (cf == nil) {
		sys->fprint(stderr, "%s: could not open %s: %r\n", prog, ctl);
		return;
	}
	df := sys->open(data, Sys->OWRITE);
	if (df == nil) {
		sys->fprint(stderr, "%s: could not open %s: %r\n", prog, data);
		return;
	}
	buff4 = array[4] of byte;
	need("RIFF");
	getl("length");
	need("WAVE");
	wave := Wave(nil, Fmt(0,0,0,0, 0), nil, nil);
	
	LOOP: for (;;) {
		a = gets(4, "tag");
		l = getl("length");
		case a {
		"cue " =>
			cues : array of Cue;
			if(dbg) sys->print("get%s\n", a);
			(l, cues) = getcue(l);
			wave.cuepoints = cues;
		"fmt " =>
			f: Fmt;
			if(dbg) sys->print("get%s\n", a);
			(l, f) = getfmt(l);
			wave.fmt = f;
		"smpl" =>
			loops: array of Loop;
			if(dbg) sys->print("get%s\n", a);
			(l, loops) = getsmpl(l);
			wave.loops = loops;
		"data" =>
			sample : array of byte;
			if(dbg) sys->print("get%s\n", a);
			(l, sample) = getdata(l);
			wave.data = sample;
			break LOOP;
		* =>
			sys->print("skipping %s\n", a);
		}
		skip(l);
	}
	
	s := "rate\t" + string wave.fmt.rate + "\n"
		+  "chans\t" + string wave.fmt.chans + "\n"
		+  "bits\t" + string wave.fmt.bits + "\n"
		+  "enc\tpcm\n";
	sys->print("%s", s);
	
	sys->print("ncues %d\tnloops %d\n", len wave.cuepoints, len wave.loops);
	for (i := 0; i < len wave.cuepoints; i++)
		sys->print("Cue: %d, %d, %d, %d\n", wave.cuepoints[i].id,
			wave.cuepoints[i].chunkstart,
			wave.cuepoints[i].blockstart,
			wave.cuepoints[i].sampleoffset);
	for (i = 0; i < len wave.loops; i++)
		sys->print("Loop: %d, %d, %d, %d, %d\n", wave.loops[i].id, wave.loops[0].looptype,
			wave.loops[i].start,
			wave.loops[i].end,
			wave.loops[i].fraction);
	sys->print("Data len %d   samples %d\n", len wave.data, len wave.data / wave.fmt.chans / (wave.fmt.bits/8));
	b := sys->aprint("%s", s);
	if (sys->write(cf, b, len b) < 0) {
		sys->fprint(stderr, "%s: could not write %s: %r\n", prog, ctl);
		return;
	}
	loop(wave, df);
}

getint(a: array of byte): int
{
	return  ((int a[0])<<16 | ((int a[1])<<24)) >> 16;
}

findzero(b: ref WaveBuf)
{
	t:=10;
	
	if(len b.wave.loops == 0)
		return;
	nbytes := b.wave.fmt.chans*(b.wave.fmt.bits/8);
	sys->print("nbytes %d  start off %d end off %d\n", nbytes, 
		b.wave.loops[0].start%nbytes,
		b.wave.loops[0].end%nbytes);
	# Align start end end sample offsets to begin on the first sample of an interlaced set.
	b.wave.loops[0].start -= b.wave.loops[0].start%nbytes;
	b.wave.loops[0].end -= b.wave.loops[0].end%nbytes;

	for (i := b.wave.loops[0].start; i < len b.wave.data; i+=nbytes){    #  i > 0; i-=nbytes){
		n := getint(b.wave.data[i-nbytes:]);
		m := getint(b.wave.data[i:]);
		if (n <= 0 && m >=0){
			b.wave.loops[0].start = i;
			sys->print("start sample %d %d  %d\n", n, m, i%nbytes);
			break;
		}
	}
	for (i = b.wave.loops[0].end; i < len b.wave.data; i+=nbytes){
		n := getint(b.wave.data[i:]);
		m := getint(b.wave.data[i+nbytes:]);
		if(n <= 0 && m >=0){
			b.wave.loops[0].end = i;
			sys->print("end sample %d %d %d\n", n, m, i%nbytes);
			break;
		}
	}
	
	if(len b.wave.cuepoints > 0){
		b.wave.cuepoints[0].sampleoffset -= b.wave.cuepoints[0].sampleoffset%nbytes;
		for (i = b.wave.cuepoints[0].sampleoffset; i > 0; i-=nbytes){
			n := getint(b.wave.data[i-nbytes:]);
			m := getint(b.wave.data[i:]);
			if(n <= 0 && m >=0){
				b.wave.cuepoints[0].sampleoffset = i;
				sys->print("release sample %d %d %d\n", n, m, i%nbytes);
				break;
			}
		}
	}
		
}

nextzero(b: ref WaveBuf, pos: int): int
{
	nbytes := b.wave.fmt.chans*b.wave.fmt.nbytes;
	for (i := pos;  i < len b.wave.data; i+=nbytes){
		n := getint(b.wave.data[i-nbytes:]);
		m := getint(b.wave.data[i:]);
		if (n <= 0 && m >=0){
			sys->print("nextzero sample %d %d  %d\n", n, m, i%nbytes);
			return i;
		}
	}
	return pos;
}

sampleoffset2bytes(b: ref WaveBuf)
{
	b.wave.loops[0].start *= b.wave.fmt.nbytes;
	b.wave.loops[0].end *= b.wave.fmt.nbytes;
	b.wave.cuepoints[0].sampleoffset *= b.wave.fmt.nbytes;
}

WaveBuf.get(b: self ref WaveBuf, n: int, a: array of byte): int
{
	nbytes := b.wave.fmt.nbytes;
	start := b.wave.loops[0].start;
	end := b.wave.loops[0].end;
	release := b.wave.cuepoints[0].sampleoffset;
#	sys->print("state %d\n", b.state);
	case b.state {
	START =>
		for (b.pos = 0; b.pos < n && b.pos < end; b.pos++)
			a[b.pos] = b.wave.data[b.pos];
		b.state = LOOPING;
		return b.pos;
	LOOPING =>
		j := 0;
		while (j < n){
			for (; j < n && b.pos < end+nbytes; b.pos++){
				a[j++] = b.wave.data[b.pos];
			}
			if(b.pos >= end+nbytes){
				b.pos = start;
				b.nloop++;
				sys->print("nloop %d  %d  %d, %d, %d\n", b.nloop, 
					getint(b.wave.data[end:]), getint(b.wave.data[start:]),
					getint(b.wave.data[end+2:]), getint(b.wave.data[start+2:]));
			}
		}
		if(b.nloop > NLOOPS){
			b.state = RELEASING;
		}
		return j;
	RELEASING =>
		releasejoin := nextzero(b, b.pos);
		sys->print("pos %d -> release join %d -> release %d -> end\n", b.pos, releasejoin, release);
		for (j := 0; j < n && b.pos < len b.wave.data && b.pos < releasejoin+nbytes; b.pos++)
			a[j++] = b.wave.data[b.pos];
		if(b.pos == releasejoin+nbytes){
			b.state = RELEASE;
			b.pos = release;
		}
		return j;
	RELEASE =>
		for (j := 0; j < n && b.pos < len b.wave.data; b.pos++)
			a[j++] = b.wave.data[b.pos];
		if (b.pos >= len b.wave.data){
			b.state = DONE;
		}
		return j;
	DONE =>
		return 0;
	}
	return 0;
}


loop(wave: Wave, df: ref Sys->FD)
{
	buf := array[Sys->ATOMICIO] of byte;
	wb := ref WaveBuf(wave, 0, 0, START);
	if(S2B)
		sampleoffset2bytes(wb);
	if(FINDZERO)
		findzero(wb);
	sys->print("start %d end %d\n", wave.loops[0].start, wave.loops[0].end);
	while((n := wb.get(len buf, buf)) > 0){
		sys->write(df, buf, n);
	}
}
