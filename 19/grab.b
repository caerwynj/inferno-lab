implement Wm0;

include "draw.m";
	draw: Draw;
	Rect, Display, Screen, Image, Point: import draw;
include "sys.m";
	sys: Sys;
include "tk.m";
	tk: Tk;
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;

Wm0: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	draw = load Draw Draw->PATH;
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	wmclient = load Wmclient Wmclient->PATH;

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	argv = tl argv;
	if(argv == nil)
		exit;
	fd := sys->create(hd argv, Sys->OWRITE, 8r666);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "open: %r \n");
		exit;
	}
	wmclient->init();
	W := wmclient->window(ctxt, "Wm0", Wmclient->Appl);
	W.startinput("ptr" :: "kbd" :: nil);
	W.reshape(Rect((0,0),(248,248)));
	W.onscreen(nil);
	for(;;) alt {
	s := <-W.ctl or
	s =  <-W.ctxt.ctl =>
		W.wmctl(s);
	p := <-W.ctxt.ptr =>
		if(W.pointer(*p))
			break;
		W.display.writeimage(fd, W.image);
	c := <-W.ctxt.kbd =>
		;
	}
}
