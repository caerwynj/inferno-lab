implement Board;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Screen, Image, Point, Rect: import draw;
include "math.m";
	math: Math;
include "ir.m";
include "mux.m";
	mux: Mux;
include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;

Board: module
{
	init:	fn(nil: ref Mux->Context, nil: list of string);
};

display: ref Display;
screen: ref Screen;
hrhand: ref Image;
minhand: ref Image;
dots: ref Image;
back: ref Image;

ZP := Point(0, 0);
first:=1;

init(ctxt: ref Mux->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	mux = load Mux Mux->PATH;
	daytime = load Daytime Daytime->PATH;
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	display = ctxt.display;
	screen = ctxt.screen;

	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;

	mainimage := screen.newwindow(screen.image.r, 0, 0);
	back = display.colormix(Draw->Palebluegreen, Draw->White);

	hrhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Darkblue);
	minhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Paleblue);
	dots = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Blue);
	drawboard(mainimage);
	mainimage.flush(Draw->Flushnow);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			sys->print("ptr %d %d\n", p.xy.x, p.xy.y);
		}
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

mkstone() : (ref Image, ref Image)
{
	center := Point(10,10);
	h := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	mask := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	h.fillellipse(center, 7, 7, display.white, ZP);
	mask.ellipse(center, 7,7, 1, display.color(20), ZP);
	mask.ellipse(center, 6,6, 1, display.color(30), ZP);
	mask.ellipse(center, 5, 5, 1, display.color(40), ZP);
	mask.ellipse(center, 4, 4, 1, display.color(50), ZP);
	mask.ellipse(center, 3, 3, 1, display.color(60), ZP);
	mask.ellipse(center, 2, 2, 1, display.color(60), ZP);
	mask.fillellipse(center, 2, 2, display.color(250), ZP);

	return (h, mask);
}

drawdots(screen: ref Image)
{
#	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
	offset := Point(18,10).add(Point(0,198));
	(dot, mask) := mkstone();
	center := Point(10,10);
	for(i := 0; i < 6; i++){   # horizontal
		for(j :=0; j < 6; j++){	# vertical
		 	p := Point(i*40, j*30);
			screen.draw(Rect(p,p.add(Point(20,20))).addpt(offset), dot, mask, ZP);
		}
	}
#	screen.draw(screen.r.addpt(Point(18,10)), layer, nil, ZP);
}


drawbackground(screen: ref Image)
{
	r := screen.r;
	
	y := r.dy();
	d := y/48;
	
	for(i:=0; i < 52; i++){
		screen.ellipse(Point(r.dx()/2, r.dy()/2), i*4, i*4, 2, display.rgb(0,0,255-(i*5)), ZP);
	}
}

drawboard(screen: ref Image)
{
	drawbackground(screen);
	drawdots(screen);
	now := daytime->now();
	drawclock(screen, now);
}

drawclock(screen: ref Image, t: int)
{
	if(screen == nil)
		return;
	tms := daytime->local(t);
	anghr := 90-(tms.hour*5 + tms.min/10)*6;
	angmin := 90-tms.min*6;
	r := Rect((0,0),(256,192));
	c := r.min.add(r.max).div(2);
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
	rad /= 2;
	rad -= 8;

#	screen.draw(screen.r, back, nil, ZP);
	(dot, mask) := mkstone();
	for(i:=0; i<12; i++){
		p := circlept(c, rad, i*(360/12));
		screen.draw(Rect(p.sub(Point(10,10)),p.add(Point(10,10))), dot, mask, ZP);
	}
#		screen.fillellipse(circlept(c, rad, i*(360/12)), 2, 2, dots, ZP);

	screen.line(c, circlept(c, (rad*3)/4, angmin), 0, 0, 1, minhand, ZP);
	screen.line(c, circlept(c, rad/2, anghr), 0, 0, 1, hrhand, ZP);

	screen.flush(Draw->Flushnow);
}

circlept(c: Point, r: int, degrees: int): Point
{
	rad := real degrees * Math->Pi/180.0;
	c.x += int (math->cos(rad)*real r);
	c.y -= int (math->sin(rad)*real r);
	return c;
}

timer(c: chan of int, ms: int)
{
	for(;;){
		sys->sleep(ms);
		c <-= 1;
	}
}
