implement Term;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Point, Rect, Font: import draw;
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;
	Window: import wmclient;
include "menuhit.m";
	menuhit: Menuhit;
	Menu, Mousectl: import menuhit;
	
include "frame.m";
	framem: Framem;
Frame, BACK, HIGH, BORD, TEXT, HTEXT, NCOL:import framem;

Term: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

display: ref Display;
ZP := Point(0, 0);
font: ref Font;
frame: ref Frame;
textcols : array of ref Draw->Image;
buf: string;

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	wmclient = load Wmclient Wmclient->PATH;
	menuhit = load Menuhit Menuhit->PATH;
	menu := ref Menu(array[] of {"exit"}, nil, 0);
	framem = load Framem Framem->PATH;
	
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	style := Wmclient->Appl;
	wmclient->init();
	if (ctxt == nil){
		ctxt = wmclient->makedrawcontext();
		style = Wmclient->Plain;
	}
	w := wmclient->window(ctxt, "Term", style);
	display = w.display;
	w.reshape(Rect((0, 0), (256, 192)));
	w.startinput("ptr" :: "kbd" :: nil);
	w.onscreen(nil);
	menuhit->init(w);
	
	font = Font.open(display, "/fonts/lucidasans/unicode.8.font");
	textcols = array[NCOL] of ref Draw->Image;
	textcols[BACK] = display.black;
	textcols[HIGH] = display.color(Draw->Darkyellow);
	textcols[BORD] = display.color(Draw->Yellowgreen);
	textcols[TEXT] = display.color(Draw->Medgreen);
	textcols[HTEXT] = display.black;
	framem->init(ctxt);
	frame = framem->newframe();
	buf = "hello world";
	
	drawboard(w.image);
	for(;;) alt{
	ctl := <-w.ctl or
	ctl = <-w.ctxt.ctl =>
		w.wmctl(ctl);
		if(ctl != nil && ctl[0] == '!'){
			drawboard(w.image);
		}else {
			framem->frsetrects(frame, w.image.r, w.image);
		}
	p := <-w.ctxt.ptr =>
		if(!w.pointer(*p)){
			if(p.buttons & 2){
				mc := ref Mousectl(w.ctxt.ptr, p.buttons, p.xy, p.msec);
				n := menuhit->menuhit(p.buttons, mc, menu, nil);
				if(n == 0){
					postnote(1, sys->pctl(0, nil), "kill");
					exit;
				}
			}else if(p.buttons & 1){
			}
		}
	c := <-w.ctxt.kbd =>
		buf[len buf] = c;
		framem->frinsert(frame, buf[len buf - 1:], 1, frame.p0);
	}
}

postnote(t : int, pid : int, note : string) : int
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (t == 1)
		note += "grp";
	sys->fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

drawboard(s: ref Image)
{
#	sys->print("rect %d %d %d %d\n", s.r.min.x, s.r.min.y, s.r.max.x, s.r.max.y);
	s.draw(s.r, textcols[BACK], nil, ZP);
	framem->frclear(frame, 0);
	framem->frinit(frame, s.r,  font, s, textcols);
	framem->frinsert(frame, buf, len buf, 0);
	framem->frdrawsel(frame, (0,0), 0, len buf, 0);
}
