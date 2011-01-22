implement Signalfs;
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
include "signal.m";
	signal: Signal;

tree: ref Tree;
treeop: chan of ref Navop;
srv: ref Styxserver;
tchan: chan of ref Tmsg;

samplerate := 22050.0;
bps := 2;		# bytes per sample; ie 16 bit two's complement little-endian
channels := 1;

Signalfs: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(sys->fildes(2), "signalfs sigmod [args ...]\n");
	exit;
}

Qroot, Qctl, Qdata: con big iota;	# paths
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	styx = load Styx Styx->PATH;
	bufio = load Bufio Bufio->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	argv = tl argv;
	if(argv == nil)
		usage();
	signal = load Signal hd argv;
	if(signal == nil){
		sys->fprint(sys->fildes(2), "module %s not found\n", hd argv);
		exit;
	}
	argv = tl argv;
	signal->init(argv);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	(tree, treeop) = nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot));
	tree.create(Qroot, dir("signalctl", 8r666, Qctl));
	tree.create(Qroot, dir("signal", 8r444, Qdata));
	(tchan, srv) = Styxserver.new(sys->fildes(0), Navigator.new(treeop), Qroot);
	pidc := chan of int;
	spawn server(tchan, srv);
}

server(tchan: chan of ref Tmsg, srv: ref Styxserver)
{
	while((gm := <-tchan) != nil) {
		pick m := gm {
		Write =>
			(c, err) := srv.canwrite(m);
			if(c == nil){
				srv.reply(ref Rmsg.Error(m.tag, err));
			}else if(c.path == Qctl){
				signal->config(string m.data);
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
				srv.reply(readstr(m, signal->configstr));
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
	d.uid = "signalfs";
	d.gid = "signalfs";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}

real2pcm(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
		if(v[i] > 32767.0)
			v[i] = 32767.0;
		else if(v[i] < -32767.0)
			v[i] = -32767.0;
		b[j++] = byte v[i];
		b[j++] = byte (int v[i] >>8);
	}
	return b;
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
		b[0:] = signal->tickFrame();
		b = b[channels:];
	}
	return buf;
}
