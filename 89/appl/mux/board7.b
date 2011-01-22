implement Board;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Screen, Image, Point, Rect, Font: import draw;
include "ir.m";
include "mux.m";
	mux: Mux;

Board: module
{
	init:	fn(nil: ref Mux->Context, nil: list of string);
};

display: ref Display;
screen: ref Screen;
ZP := Point(0, 0);
font: ref Font;

init(ctxt: ref Mux->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	display = ctxt.display;
	screen = ctxt.screen;
	screen.image.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;
	font = Font.open(display, "/fonts/vera/Vera/Vera.14.font");

	drawboard(screen.image);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
		}
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

animate(nil: Point)
{}

mkhline() : ref Image
{
	lmask := display.newimage(Rect((0,0),(1,9)), Draw->RGBA32, 1, Draw->Transparent);
	
	lmask.draw(Rect((0, 0),(1, 1)), display.color(10), nil, ZP);
	lmask.draw(Rect((0, 1),(1, 2)), display.color(40), nil, ZP);
	lmask.draw(Rect((0, 2),(1, 3)), display.color(60), nil, ZP);
	lmask.draw(Rect((0, 3),(1, 4)), display.color(80), nil, ZP);
	lmask.draw(Rect((0, 4),(1, 5)), display.color(200), nil, ZP);
	lmask.draw(Rect((0, 5),(1, 6)), display.color(80), nil, ZP);
	lmask.draw(Rect((0, 6),(1, 7)), display.color(60), nil, ZP);
	lmask.draw(Rect((0, 7),(1, 8)), display.color(40), nil, ZP);
	lmask.draw(Rect((0, 8),(1, 9)), display.color(10), nil, ZP);
	return lmask;
}

drawboard(s: ref Image)
{
	if(s == nil)
		  return;
	s.draw(s.r, display.black, nil, ZP);
	msk := mkhline();
	k:=1;
	im := display.newimage(Rect((0,0),(1,9)), Draw->RGBA32, 1, Draw->Transparent);
	im.draw(msk.r, display.white, msk, ZP);
	p := array[] of {Point(15,0+k), Point(30-k,8), Point(30-k,22),
			Point(15,30-k), Point(0+k,22), Point(0+k,8), Point(15,0+k)};
	s.bezspline(p[2:5], 0, 0, 3, im, ZP);
	s.flush(Draw->Flushnow);
}

