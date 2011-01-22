implement Tmpl0;
include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
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
	y:= array[100] of real;
	io := bufio->fopen(sys->fildes(0), bufio->OREAD);
	while((t := io.gett(" \n\r\t")) != nil){
		if(n >= len y)
			y = (array[len y + 100] of real)[0:] = y;
		y[n++] = real t;
	}
	ffts->ffts(y[0:n], array[n] of {* => 0.0}, n, n, n, 1);
	for(i:=0;i<n;i++)
		print("%g\n", y[i]);
}
