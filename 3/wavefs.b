implement Wavefs;
include "sys.m";
	sys: Sys;
	fildes, read, write: import sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator, Navop, readbytes, readstr: import styxservers;
	nametree: Nametree;
	Tree: import nametree;
include "math.m";
	math: Math;
	Pi, sin, fabs: import math;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

tree: ref Tree;
treeop: chan of ref Navop;
srv: ref Styxserver;
tchan: chan of ref Tmsg;

samplerate := 22050.0;
pitch := 440.0;
bits := 16;
bps := 2;		# bytes per sample; ie 16 bit two's complement little-endian
channels := 1;
data: array of real;
rate:=1.0;
gain := 1.0;
time := 0.0;
swab := 0;
configstr :string ;

Wavefs: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "wavefs wavefile\n");
	exit;
}

Qroot, Qctl, Qdata: con big iota;	# paths
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	styx = load Styx Styx->PATH;
	bufio = load Bufio Bufio->PATH;

	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	argv = tl argv;
	if(argv == nil)
		usage();
	data = readfile(hd argv);
	mconfig("pitch 440.0");
#	setfreq(pitch);
#	normalize(1.0);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	(tree, treeop) = nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot));
	tree.create(Qroot, dir("wavectl", 8r666, Qctl));
	tree.create(Qroot, dir("wave", 8r444, Qdata));
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(treeop), Qroot);
	pidc := chan of int;
	spawn server(tchan, srv);
}

server(tchan: chan of ref Tmsg, srv: ref Styxserver)
{
	sys->pctl(Sys->NEWPGRP, nil);
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Write =>
			(c, err) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
			}else if(c.path == Qctl){
				mconfig(string m.data);
				srv.reply(ref Rmsg.Write(m.tag, len m.data));
			}
		Read =>
			(c, err) := srv.canread(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
			}else if(c.path == Qdata){
# reads should be multiple of bytepersample * channels e.g. 2 for 16bit mono.
# number of frames to read is count / bps 
				b := real2pcm(tickBlock(m.count/(bps*channels)));
				srv.reply(ref Rmsg.Read(m.tag, b));
			}else if(c.path == Qctl){
				srv.reply(readstr(m, configstr));
			}else 
				srv.default(gm);
		* =>
			srv.default(gm);
		}
	}
	tree.quit();
}

dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = "wavefs";
	d.gid = "wavefs";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}

mconfig(s: string)
{
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"pitch" =>
		pitch = real hd tl flds;
		setfreq(pitch);
	}
	configstr = sys->sprint("rate %d\nchans %d\nfreq %g\n", int samplerate, channels, pitch);
}

real2pcm(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
#		v[i] *= 32767.0;
		if(v[i] > 32767.0)
			v[i] = 32767.0;
		else if(v[i] < -32767.0)
			v[i] = -32767.0;
		b[j++] = byte v[i];
		b[j++] = byte (int v[i] >>8);
	}
	return b;
}

readfile(file: string): array of real
{
	n := 0;
	r : real;
	y := array[8] of real;
	io := bufio->open(file, bufio->OREAD);
	for(;;){
	 	(b, eof) := getw(io);
		if(eof)
			break;
		if(n >= len y)
			y = (array[len y * 2] of real)[0:] = y;
		r = real b;
#		if(r != 0.0)
#			r /= 32767.0;
		y[n++] = r;
	}
	return y[0:n];
}

getw(io: ref Iobuf): (int, int)
{
	b:= array[2] of int;
	for(i:=0;i<2;i++){
		b[i] = io.getb();
		if(b[i] == bufio->EOF)
			return (0, 1);
	}
	if(swab)
		n := b[1]<<24 | b[0] << 16;
	else 
		n = b[0]<<24 | b[1] << 16;
	return (n >> 16, 0);
}

normalize(data: array of real, peak: real)
{
	max := 0.0;

	for(i := 0; i < len data; i++)
		if(fabs(data[i])>max)
			max = fabs(data[i]);
	if(max >0.0){
		max = 1.0/max;
		max *= peak;
		for(i = 0; i < len data; i++)
			data [i] *= max;
	}
}

tickBlock(n: int): array of real
{
	buf := array[n] of real;
	b := buf[0:];
	for(i:=0; i < n; i+=channels){
		b[0:] = tickFrame();
		b = b[channels:];
	}
	return buf;
}

# next sample for n channels
tickFrame(): array of real
{
	out :=array[channels] of real;
	index : int;
	alpha : real;

	while(time < 0.0)
		time += real len data;
	while(time >= real len data)
		time -= real len data;
	index = int time;
	alpha = time - real index;
	index *= channels;
	for(i:=0; i<channels; i++){
		out[i] = data[index%(len data)];
		out[i] += (alpha * (data[(index+channels)%(len data)] - out[i]));
		index++;
	}
	time += rate;
	return out;
}

setfreq(freq: real)
{
	rate = real(len data) * freq / samplerate;
}
