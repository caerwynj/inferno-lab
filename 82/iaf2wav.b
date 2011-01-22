################################################################################
# Read an iaf file and convert it to a wav on the standard output.
# Hugo Rivera - uair00@gmail.com
################################################################################

implement Iaf2wav;

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

Iaf2wav : module
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
		"bits"  =>
			bits = int val;
		"enc" =>
			enc = val;
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

	off := outf.seek(big 44, Bufio->SEEKSTART);
	if(off != big 44)
		readerror(progname);

	# Copy data from the iaf file to the wav file.
	buff := array [Sys->ATOMICIO] of byte;

	m : int;
	datasize := 0;
	do {
		n = inf.read(buff, Sys->ATOMICIO);
		if(n == Bufio->ERROR)
			readerror(progname);
		m = outf.write(buff, n);
		if(m != n)
			writeerror(progname);
		datasize += n;
	} while(n > 0);

	# Put the wav file header.
	off = outf.seek(big 0, Bufio->SEEKSTART);
	if(off != big 0)
		readerror(progname);

	whdr := array [44] of byte;

	fsize := datasize + 36;
	byterate := rate * chans * bits / 8;
	blockalign := chans * bits / 8;

	whdr[0] = byte 'R';
	whdr[1] = byte 'I';
	whdr[2] = byte 'F';
	whdr[3] = byte 'F';
	whdr[4] = byte (fsize & 16rFF);
	whdr[5] = byte (fsize >> 8 & 16rFF);
	whdr[6] = byte (fsize >> 16 & 16rFF);
	whdr[7] = byte (fsize >> 24 & 16rFF);
	whdr[8] = byte 'W';
	whdr[9] = byte 'A';
	whdr[10] = byte 'V';
	whdr[11] = byte 'E';
	whdr[12] = byte 'f';
	whdr[13] = byte 'm';
	whdr[14] = byte 't';
	whdr[15] = byte ' ';
	# Just PCM for now.
	whdr[16] = byte 16r10;
	whdr[17] = byte 16r00;
	whdr[18] = byte 16r00;
	whdr[19] = byte 16r00;
	whdr[20] = byte 16r01;
	whdr[21] = byte 16r00;
	whdr[22] = byte (chans & 16rFF);
	whdr[23] = byte (chans >> 8 & 16rFF);
	whdr[24] = byte (rate & 16rFF);
	whdr[25] = byte (rate >> 8 & 16rFF);
	whdr[26] = byte (rate >> 16 & 16rFF);
	whdr[27] = byte (rate >> 24 & 16rFF);
	whdr[28] = byte (byterate & 16rFF);
	whdr[29] = byte (byterate >> 8 & 16rFF);
	whdr[30] = byte (byterate >> 16 & 16rFF);
	whdr[31] = byte (byterate >> 24 & 16rFF);
	whdr[32] = byte (blockalign & 16rFF);
	whdr[33] = byte (blockalign >> 8 & 16rFF);
	whdr[34] = byte (bits & 16rFF);
	whdr[35] = byte (bits >> 8 & 16rFF);
	whdr[36] = byte 'd';
	whdr[37] = byte 'a';
	whdr[38] = byte 't';
	whdr[39] = byte 'a';
	whdr[40] = byte (datasize & 16rFF);
	whdr[41] = byte (datasize >> 8 & 16rFF);
	whdr[42] = byte (datasize >> 16 & 16rFF);
	whdr[43] = byte (datasize >> 24 & 16rFF);

	m = outf.write(whdr, 44);
	if(m != 44)
		writeerror(progname);

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
