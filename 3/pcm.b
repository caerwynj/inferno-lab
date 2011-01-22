implement Tmpl0;
include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf, EOF: import bufio;
include "math.m";
	math: Math;
	sin: import math;
include "ffts.m";
	ffts: FFTs;

Tmpl0: module {init: fn(nil: ref Draw->Context, argv: list of string);};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	ffts = load FFTs FFTs->PATH;

	n := 0;
	y:= array[8] of int;
	io := bufio->fopen(sys->fildes(0), bufio->OREAD);
	for(;;){
	 	(b, eof) := getw(io);
		if(eof)
			break;
		if(n >= len y)
			y = (array[len y * 2] of int)[0:] = y;
		y[n++] = b;
	}
	for(i:=0;i<n;i++)
		print("%d\n", y[i]);
}

getw(io: ref Iobuf): (int, int)
{
	b:= array[2] of int;
	for(i:=0;i<2;i++){
		b[i] = io.getb();
		if(b[i] == EOF)
			return (0, 1);
	}
	n := b[1]<<24 | b[0] << 16;
#	n := b[0]<<24 | b[1] << 16;
	return (n >> 16, 0);
}
