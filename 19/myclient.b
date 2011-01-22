implement Myclient;
include "sys.m";
	sys: Sys;
	fprint, open, sprint, pctl: import sys;
include "draw.m";
	draw: Draw;
	Display, Image, Screen, Rect, Point, Pointer, 
		Wmcontext, Context, Font: import draw;
include "wmlib.m";
	wmlib: Wmlib;
	qword, splitqword, s2r: import wmlib;

Myclient: module
{
	init:		fn(ctxt: ref Draw->Context, argv: list of string);
	window:		fn(ctxt: ref Draw->Context, r: Rect): ref Window;
};

Window: adt{
	display:	ref Draw->Display;
	screen:	ref Draw->Screen;
	image: ref Draw->Image;
	r: 	Draw->Rect;		# full rectangle of window, including titlebar.
	displayr: Draw->Rect;
	ctxt: 	ref Draw->Wmcontext;
	bd:		int;
	focused: int;

	wmctl:	fn(w: self ref Window, request: string): string;
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmlib = load Wmlib Wmlib->PATH;

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	wmlib->init();
	w := window(ctxt, Rect((0,0),(248,248)));
	w.wmctl("start ptr");
	w.wmctl("start kbd");
	w.wmctl(sys->sprint("!reshape . -1 %s place", r2s(w.r)));
	for(;;) alt {
	s :=  <-w.ctxt.ctl =>
		w.wmctl(s);
	p := <-w.ctxt.ptr =>
		if(p.buttons & 4 && inborder(w, p.xy))
			w.wmctl("exit");
		else if(p.buttons & 2 && inborder(w, p.xy))
			w.wmctl(sys->sprint("!size . -1 0 0"));
		else if(p.buttons & 1 && inborder(w, p.xy)){
			w.wmctl(sys->sprint("!move . -1 %d %d", p.xy.x, p.xy.y));
		}else if(p.buttons &1)
			w.image.fillellipse(p.xy, 1, 3, w.display.black, (0,0));
	c := <-w.ctxt.kbd =>
		;
	}
}

blankwin: Window;
window(ctxt: ref Draw->Context, r: Rect): ref Window
{
	w := ref blankwin;
	w.ctxt = wmlib->connect(ctxt);
	w.display = ctxt.display;
	readscreenrect(w);
	w.bd = 5;
	w.r = r.inset(-w.bd);
	w.wmctl("fixedorigin");
	return w;
}

putimage(w: ref Window, i: ref Image, nil: string)
{
	if(w.screen != nil && i == w.screen.image)
		return;
	display := w.ctxt.ctxt.display;
	w.screen = Screen.allocate(i, w.display.color(Draw->White), 0);
	ir := i.r.inset(w.bd);
	if(ir.dx() < 0)
		ir.max.x = ir.min.x;
	if(ir.dy() < 0)
		ir.max.y = ir.min.y;
	w.image = w.screen.newwindow(ir, Draw->Refnone, Draw->White);
	drawborder(w);
	w.r = i.r;
}

# draw an imitation tk border.
drawborder(w: ref Window)
{
	if(w.screen == nil)
		return;
	if(w.focused)
		col := w.display.color(Draw->Paleblue);
	else
		col = w.display.color(Draw->Greyblue);
	i := w.screen.image;
	r := w.screen.image.r;
	i.draw((r.min, (r.min.x+w.bd, r.max.y)), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.min.y), (r.max.x, r.min.y+w.bd)), col, nil, (0, 0));
	i.draw(((r.max.x-w.bd, r.min.y+w.bd), r.max), col, nil, (0, 0));
	i.draw(((r.min.x+w.bd, r.max.y-w.bd), (r.max.x-w.bd, r.max.y)), col, nil, (0, 0));
}

inborder(w: ref Window, p: Point): int
{
	r := w.screen.image.r;
	return (Rect(r.min, (r.min.x+w.bd, r.max.y))).contains(p) ||
		(Rect((r.min.x+w.bd, r.min.y), (r.max.x, r.min.y+w.bd))).contains(p) ||
		(Rect((r.max.x-w.bd, r.min.y+w.bd), r.max)).contains(p) ||
		(Rect((r.min.x+w.bd, r.max.y-w.bd), (r.max.x-w.bd, r.max.y))).contains(p);
}

readscreenrect(w: ref Window)
{
	if((fd := sys->open("/chan/wmrect", Sys->OREAD)) != nil){
		buf := array[12*4] of byte;
		n := sys->read(fd, buf, len buf);
		if(n > 0){
			(w.displayr, nil) = s2r(string buf[0:n], 0);
			return;
		}
	}
	w.displayr = w.display.image.r;
}

Window.wmctl(w: self ref Window, req: string): string
{
	(c, next) := qword(req, 0);
	case c {
	"exit" =>
		fprint(open("/prog/" + string pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp");
		exit;
	"ok" or "help" or "task" or "untask" =>
		;
	"rect" =>
		(w.displayr, nil) = s2r(req, next);
	"haskbdfocus" =>
		w.focused = int qword(req, next).t0;
		drawborder(w);
	* =>
		name: string;
		if(req != nil && req[0] == '!'){
			(name, next) = qword(req, next);
		}
		if(w.ctxt.connfd != nil){
			if(sys->fprint(w.ctxt.connfd, "%s", req) == -1)
				return sys->sprint("%r");
			if(req[0] == '!')
				recvimage(w, name);
		}
	}
	return nil;
}

recvimage(w: ref Window, tag: string)
{
	i := <-w.ctxt.images;
	if(i == nil)
		i = <-w.ctxt.images;
	putimage(w, i, tag);
}

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}
