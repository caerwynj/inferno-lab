################################################################################
# Read a text file and output the values in iaf format on stdout.
# Hugo Rivera - uair00@gmail.com
################################################################################

implement Txt2iaf;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;
include "string.m";
	str : String;
include "arg.m";
	arg : Arg;

stdin : ref Sys->FD;
stdout : ref Sys->FD;
stderr : ref Sys->FD;

inf : ref Iobuf;
outf : ref Iobuf;

FALSE : con 0;
TRUE : con 1;
EMPTY : con 3;

Txt2iaf : module
{
	init : fn(nil : ref Draw->Context, args : list of string);
};

init(nil : ref Draw->Context, args : list of string)
{
	rate := 44100;
	bits := 16;
	chans := 1;
	pad	:= array[] of { "  ", " ", "", "   " };

	progname := hd args;

	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmodule(progname, Bufio->PATH);
	str = load String String->PATH;
	if(str == nil)
		badmodule(progname, String->PATH);
	arg = load Arg Arg->PATH;
	if(arg == nil)
		badmodule(progname, Arg->PATH);

	arg->init(args);
	arg->setusage(progname + " [-c chans] [-r rate] [-bw] [file]");
	while((c := arg->opt()) != 0)
		case c {
		'c' =>
			sc := arg->earg();
			chans = int sc;
			if(chans < 1 || chans > 2)
				badarg(progname, sc);
		'r' =>
			sr := arg->earg();
			rate = int sr;
			if(rate <= 0)
				badarg(progname, sr);
		'b' =>
			bits = 8;
		'w' =>
			bits = 16;
		* =>
			arg->usage();
		}
	args = arg->argv();
	if(len args > 1)
		arg->usage();
	arg = nil;

	if(len args == 1)
		inf = bufio->open(hd args, Bufio->OREAD);
	else
		inf = bufio->fopen(stdin, Bufio->OREAD);
	if(inf == nil)
		openerror(progname);

	outf = bufio->fopen(stdout, Bufio->OWRITE);
	if(outf == nil)
		openerror(progname);

	auhdr := "rate\t" + string rate + "\n" +
			 "chans\t" + string chans + "\n" +
			 "bits\t" + string bits + "\n" +
			 "enc\tpcm";
	auhdr += pad[len auhdr % 4] + "\n\n";
	n := outf.puts(auhdr);
	if(n == Bufio->ERROR)
		writeerror(progname);

	val : int;

	for(oline := inf.gets('\n'); oline != nil; oline = inf.gets('\n')) {
		line := stripcom(oline);
		n = checkl(line);
		if(n == FALSE)
			notiaf(progname);
		else if(n == EMPTY)
			continue;
		for(i := 0; i < chans; i++) {
			(val, line) = str->toint(line, 10);
			nbytes := bits/8;
			if(val < 0)
				val += 1 << bits;
 			data := array [nbytes] of byte;
			for(j := 0; j < nbytes; j++)
				data[j] = byte (val >> 8 * j & 16rFF);
			n = outf.write(data, nbytes);
			if(n != nbytes)
				writeerror(progname);
		}
	}

	iocloser();
}

# Close open buffers.
iocloser()
{
	if(inf != nil)
		inf.close();
	if(outf != nil)
		outf.close();
}

# Error functions.
badmodule(progname, mod : string)
{
	sys->fprint(stderr, "%s: Cannot load %s: %r\n", progname, mod);
	raise "fail: bad module";
}

badarg(progname, argm : string)
{
	sys->fprint(stderr, "%s: Bad argument -- %s\n", progname, argm);
	raise "fail: bad arg";
}

openerror(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Cannot open file: %r\n", progname);
	raise "fail: open error";
}

notiaf(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Cannot convert text file to iaf.\n", progname);
	raise "fail: not iaf";
}

readerror(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Read error: %r\n", progname);
	raise "fail: read error";
}

writeerror(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Cannot write to file: %r\n", progname);
	raise "fail: write error";
}

# Strip comments and the new line character from a string.
stripcom(s : string) : string
{
	s = s[0:len s - 1];
	for(i := 0; i < len s; i++)
		if(s[i] == '#') {
			s = s[0:i];
			break;
		}
	return s;
}

# Check if line is valid.
checkl(s : string) : int
{
	status := EMPTY;

	for(i := 0; i < len s; i++)
		case s[i] {
		'0' or '1' or '2' or '3' or '4' or '5' or '6' or '7' or '8' or '9' or
		'-' =>
			status = status & TRUE;
		' ' or '\t' =>
			status = status & EMPTY;
		* =>
			status = FALSE;
			break;
	}

	return status;
}
