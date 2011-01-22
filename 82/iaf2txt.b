################################################################################
# Read an iaf file and output the values in text format.
# Hugo Rivera - uair00@gmail.com
################################################################################

implement Iaf2txt;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio : Bufio;
	Iobuf : import bufio;

stdin : ref Sys->FD;
stdout : ref Sys->FD;
stderr : ref Sys->FD;

inf : ref Iobuf;
outf : ref Iobuf;

Iaf2txt : module
{
	init : fn(nil : ref Draw->Context, args : list of string);
};

init(nil : ref Draw->Context, args : list of string)
{
	progname := hd args;

	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badmodule(progname, Bufio->PATH);

	if(len args > 2)
		usage(progname);

	if(len args == 2)
		inf = bufio->open(hd tl args, Bufio->OREAD);
	else
		inf = bufio->fopen(stdin, Bufio->OREAD);
	if(inf == nil) 
		openerror(progname);

	shdr := inf.gets('\n');
	if(shdr == nil)
		readerror(progname);
	if(len shdr < 7)
		notiaf(progname);
	if(shdr[0 : 4] != "rate")
		notiaf(progname);

	rate := int shdr[5 : ];
	if(rate <= 0)
		notiaf(progname);

	chans, bits : int;
	enc : string;
	for(i := 0; i < 3; i++) {
		shdr = inf.gets('\n');	
		if(shdr == nil) 
			readerror(progname);
		shdr = shdr[0 : len shdr - 1];
		(nil, alst) := sys->tokenize(shdr, "\t");
		if(len alst != 2)
			notiaf(progname);
		word := hd alst;
		val :=  hd tl alst;
		case word {
		"chans" =>
			chans = int val;
			if(chans <= 0)
				notiaf(progname);
		"bits"  =>
			bits = int val;
			if(bits <= 0)
				notiaf(progname);
		"enc" =>
			enc = val;
			if(enc[0 : 3] != "pcm") {
				sys->fprint(stderr,
						"%s: Sorry, only pcm encoding supported so far.\n",
						progname);
				raise "fail: unsupported encoding";
			}
		* =>
			notiaf(progname);
		}
	}

	# Avoid the empty line.
	n := inf.getb();
	if(n == Bufio->ERROR)
		readerror(progname);

	outf = bufio->fopen(stdout, Bufio->OWRITE);
	if(outf == nil)
		openerror(progname);

	# Print output file header, that's some useful info. Everything from the
	# numeral symbol '#' to	the end of line is to be treated as a comment by
	# anyone or anything reading this file.
	smsg := "# Inferno audio file converted to utf.\n" +
			"# rate " + string rate	+ "\n" +
			"# chans " + string chans +"\n" +
			"# bits " + string bits + "\n" + 
			"# enc " + enc + "\n\n";

	n = outf.puts(smsg);
	if(n == Bufio->ERROR)
		writeerror(progname);

	# Start reading the audio data and write it in the output file.
	samplesz := bits/8;
	for(i = 0; ; i++) {
		val := 0;
		data := array [samplesz] of byte;

		n = inf.read(data, samplesz);
		if(n == Bufio->ERROR)
			readerror(progname);
		else if(n != samplesz)
			break;

		for(j := 0; j < samplesz; j++)
			val = (int data[j]) << 8 * j | val;
		if(val >= 1 << bits - 1)
			val -= 1 << bits;
		sval := string val;
		if(i % chans)
			sval += "\t";
		else
			sval += "\n";
		m := outf.puts(sval);
		if(m == Bufio->ERROR)
			writeerror(progname);
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

openerror(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Cannot open file: %r\n", progname);
	raise "fail: open error";
}

notiaf(progname : string)
{
	iocloser();
	sys->fprint(stderr, "%s: Not an iaf file\n", progname);
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

usage(progname : string)
{
	sys->fprint(stderr, "Usage: %s [infile]\n", progname);
	raise "fail: usage";
}
