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

pad	:= array[] of { "  ", " ", "", "   " };

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

init(nil: ref Draw->Context, argv: list of string)
{
	l: int;
	a: string;

	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	prog = hd argv;
	argv = tl argv;
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
	for (;;) {
		a = gets(4, "tag");
		l = getl("length");
		if (a == "fmt ")
			break;
		skip(l);
	}
	if (getw("format") != 1)
		error("not PCM");
	chans := getw("channels");
	rate := getl("rate");
	getl("AvgBytesPerSec");
	getw("BlockAlign");
	bits := getw("bits");
	l -= 16;
	do {
		skip(l);
		a = gets(4, "tag");
		l = getl("length");
	}
	while (a != "data");
	s := "rate\t" + string rate + "\n"
		+  "chans\t" + string chans + "\n"
		+  "bits\t" + string bits + "\n"
		+  "enc\tpcm\n";
	b := sys->aprint("%s", s);
	if (sys->write(cf, b, len b) < 0) {
		sys->fprint(stderr, "%s: could not write %s: %r\n", prog, ctl);
		return;
	}
	if (sys->stream(inf, df, Sys->ATOMICIO) < 0) {
		sys->fprint(stderr, "%s: could not stream %s: %r\n", prog, data);
		return;
	}
}
