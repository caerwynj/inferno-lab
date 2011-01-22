implement Tmpl0;
include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
	sin: import math;
include "gr.m";
	gr: GR;
	Plot: import gr;

Tmpl0: module {init: fn(nil: ref Draw->Context, argv: list of string);};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	gr = load GR GR->PATH;
	p := gr->open(ctxt, "plot");
	n := 0;
	y:= array[100] of real;
	io := bufio->fopen(sys->fildes(0), bufio->OREAD);
	while((t := io.gett(" \n\r\t")) != nil){
		if(n >= len y)
			y = (array[len y + 100] of real)[0:] = y;
		y[n++] = real t;
	}
	x:=array[n] of real;
	for(i:=0;i<n;i++)
		x[i] = real i;
	p.pen(gr->REFERENCE);
	p.graph(x, y);
	p.paint("", nil, "", nil);
	p.bye();
}
