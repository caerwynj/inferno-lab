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
			return;
		}
	}
}

animate(nil: Point)
{}

drawboard(s: ref Image)
{
	 if(s == nil)
		   return;
	 s.draw(s.r, display.black, nil, ZP);

	 s.flush(Draw->Flushnow);
}

