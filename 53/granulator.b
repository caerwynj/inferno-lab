implement Signal;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
include "dsp.m";
	dsp: Dsp;
	samplerate, channels, bps, Granulate, File: import dsp;
include "arg.m";
	arg: Arg;

pitch := 440.0;
gran: ref Granulate;
configstr: string;

Signal: module {
	init:fn(ctxt: ref Draw->Context, args: list of string);
};


init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;
	arg = load Arg Arg->PATH;
	dsp->init(nil);
	arg->init(args);
	stretch := 4;
	voices := 1;
	while((o := arg->opt()) != 0)
		case o {
		's' =>
			stretch = int arg->earg();
		'v' =>
			voices = int arg->earg();
		}
	args = arg->argv();
	if(len args != 1)
		exit;
	gran = Granulate.mk(hd args);	
	gran.stretch = stretch;
	gran.setvoices(voices);
	sys->pctl(Sys->NEWPGRP, nil);
	stdout := sys->fildes(1);
	cnt := gran.raw.length * stretch;
	while (cnt > 0) {
		b := read(1024*8);
		sys->write(stdout, b, len b);
		cnt -= (len b / 2);
	}
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	buf := array[nsamples] of real;
	b: array of real;
	b = buf[0:];
	for(i:=0; i<nsamples; i+=channels){
		b[0] = gran.tick();
		b = b[channels:];
	}
	return dsp->norm2raw(buf);
}
