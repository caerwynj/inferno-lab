implement Scope;

include "draw.m";
	draw: Draw;
	Rect, Image, Display, Screen, Point: import draw;
include "sys.m";
	sys: Sys;
	sprint, print: import sys;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "arg.m";
	arg: Arg;

Scope: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

pic: ref Image;
display: ref Display;
chans := 1;
rate := 22050;
fps := 25;			# frames per second

usage()
{
	sys->fprint(sys->fildes(2), "scope -1248ms\n");
	exit;
}

init(ctxt: ref Draw->Context, args: list of string)
{
	draw = load Draw Draw->PATH;
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	arg = load Arg Arg->PATH;

	arg->init(args);
	while((opt := arg->opt()) != 0)
		case opt {
		'm' => chans = 1;
		's' => chans = 2;
		'8' => rate = 8000;
		'1' => rate = 11025;
		'2' => rate = 22050;
		'4' => rate = 44100;
		* =>
			usage();
		}
	args = arg->argv();
	
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	tkclient->init();
	(top, ctl) := tkclient->toplevel(ctxt, nil, "Tk0", Tkclient->Appl);

	cc := chan of string;
	tick := chan of int;
	tk->namechan(top, cc, "grcmd");
	cmd(top, "panel .c -width 248 -height 248");
	cmd(top, "pack .c; update");
	cmd(top, "bind .c <ButtonPress-1> {send grcmd down1,%x,%y}");

	display = ctxt.display;
	pic = display.newimage(Rect((0,0),(248,248)), Draw->RGB24, 0, Draw->White);
	tk->putimage(top, ".c", pic, nil);
	tkclient->startinput(top, "ptr" :: "kbd" :: nil);
	tkclient->onscreen(top, nil);
	spawn timer(tick);
	for(;;) alt {
	s := <-ctl or
	s =  <-top.ctxt.ctl or
	s = <-top.wreq =>
		tkclient->wmctl(top, s);
	p := <-top.ctxt.ptr =>
		tk->pointer(top, *p);
	c := <-top.ctxt.kbd =>
		tk->keyboard(top, c);
	press := <-cc =>
		(nn,cmds) := sys->tokenize(press,",");
		if(cmds==nil) 
			continue;
		case hd cmds {
		"down1" =>
			x := int(hd tl cmds);
			y := int(hd tl tl cmds);
		}
	<-tick =>
			r := readsample(rate * chans / fps);
			redraw(r);
			tk->putimage(top, ".c", pic, nil);
			tk->cmd(top, "update");
	}
}

cmd(t: ref Tk->Toplevel, arg: string): string
{
	rv := tk->cmd(t,arg);
	if(rv!=nil && rv[0]=='!')
		print("tk->cmd(%s): %s\n",arg,rv);
	return rv;
}


redraw(b: array of real)
{
	pic.draw(pic.r, display.white, nil, (0,0));
	if(chans == 2){
		pic.poly(real2point(b, 0), Draw->Enddisc, Draw->Enddisc, 1, display.color(Draw->Red), (0,0));
		pic.poly(real2point(b, 1), Draw->Enddisc, Draw->Enddisc, 1, display.color(Draw->Green), (0,0));
	}else
		pic.poly(real2point(b, 0), Draw->Enddisc, Draw->Enddisc, 1,  display.black, (0,0));
}

real2point(r: array of real, c: int): array of Point
{
	p:= array[len r] of Point;
	n := len r / chans / 248;
	j := 0;
	for(i := c; i < len r; i += n*chans){
		p[j] = Point(j, int((r[i]/32768.0)*124.0 + 124.0));
		j++;
	}
	return p[0:j];
}

readsample(nsamples: int): array of real
{
	buf:= array[nsamples*2] of byte;
	b: array of byte;
	out:= array[nsamples] of real;
	nb := sys->read(sys->fildes(0), buf, len buf);
	sys->write(sys->fildes(1), buf, nb);
	b=buf[0:nb];
	for(i:=0;i<nb/2;i++){
		out[i] = real ((int b[1]<<24 | int b[0] << 16) >> 16);
		b = b[2:];
	}
	return out[0:i];
}

timer(tick: chan of int)
{
	for(;;){
		sys->sleep(40);
		tick <-= 1;
	}
}
