implement Board;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Screen, Image, Point, Rect, Pointer: import draw;

include "math.m";
	math: Math;

include "daytime.m";
	daytime: Daytime;
	Tm: import daytime;
include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;


Board: module
{
	init:	fn(nil: ref Mux->Context, nil: list of string);
};

hrhand: ref Image;
minhand: ref Image;
dots: ref Image;
halo: ref Image;
mask: ref Image;
back: ref Image;
display: ref Display;
screen: ref Screen;

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
	back = display.colormix(Draw->Palebluegreen, Draw->White);

	hrhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Darkblue);
	minhand = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Paleblue);
	dots = display.newimage(Rect((0,0),(1,1)), Draw->CMAP8, 1, Draw->Blue);

	now := daytime->now();
	drawboard(screen.image, now);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartkbd;
	ctxt.ctomux <-= Mux->AMstartir;

	sys->print("hi\n");
	ticks := chan of int;
	spawn timer(ticks, 30*1000);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			sys->print("ptr %d %d\n", p.xy.x, p.xy.y);
			drawstone(screen.image, p.xy);
		}
	k := <-ctxt.ckbd =>
		;
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
#			postnote(1, sys->pctl(0, nil), "kill");
			ctxt.ctomux <- = Mux->AMexit;
			return;
		}
	<-ticks =>
		t := daytime->now();
		if(t != now){
			now = t;
			drawboard(screen.image, now);
		}
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

ZP := Point(0, 0);
first:=1;

mkstone() : (ref Image, ref Image)
{
	center := Point(10,10);
	halo = display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->White);
	mask = display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
#	halo.fillellipse(center, 10, 10, display.white, ZP);
	mask.ellipse(center, 10, 10, 1, display.color(10), ZP);
	mask.ellipse(center, 8, 8, 1, display.color(20), ZP);
	mask.ellipse(center, 6, 6, 1, display.color(75), ZP);
	mask.fillellipse(center, 4, 4, display.color(250), ZP);
#	mask.ellipse(center, 2, 2, 2, display.color(200), ZP);

	return (halo, mask);
}

mkhline(length, thick: int) : (ref Image, ref Image)
{
	line := display.newimage(Rect((0,0), (length, 8)),  Draw->RGBA32, 0, Draw->White);
	lmask := display.newimage(Rect((0,0),(length, 8)), Draw->RGBA32, 0, Draw->Transparent);
	
#	line.line(Point(0,0), Point(length,0), 0, 0, 4, display.white, ZP);
	lmask.draw(Rect((0,0), (length, 8)), display.color(75), nil, ZP);
#	lmask.line(Point(0,0), Point(length, 0), 0, 0, 4, display.color(75), ZP);
#	lmask.line(Point(0,1), Point(length, 1), 0, 0, 0, display.color(75), ZP);
	lmask.line(Point(0,2), Point(length, 2), 0, 0, 1, display.color(100), ZP);
#	lmask.line(Point(0,3), Point(length, 3), 0, 0, 0, display.color(75), ZP);
#	lmask.line(Point(0,4), Point(length, 4), 0, 0, 0, display.color(75), ZP);
#	lmask.line(Point(0,5), Point(length, 5), 0, 0, 0, display.color(50), ZP);
#	lmask.line(Point(0,6), Point(length, 6), 0, 0, 0, display.color(50), ZP);
	return(line, lmask);
}

mkvline(length, thick: int) : (ref Image, ref Image)
{
	line := display.newimage(Rect((0,0), (8, length)),  Draw->RGBA32, 0, Draw->White);
	lmask := display.newimage(Rect((0,0),(8, length)), Draw->RGBA32, 0, Draw->Transparent);
	
#	line.line(Point(0,0), Point(length,0), 0, 0, 4, display.white, ZP);
	lmask.line(Point(0,0), Point(0,length), 0, 0, 0, display.color(50), ZP);
	lmask.line(Point(1,0), Point(1,length), 0, 0, 0, display.color(75), ZP);
	lmask.line(Point(2,0), Point(2,length), 0, 0, 0, display.color(100), ZP);
	lmask.line(Point(3,0), Point(3,length), 0, 0, 0, display.color(75), ZP);
	lmask.line(Point(4,0), Point(4,length), 0, 0, 0, display.color(75), ZP);
	lmask.line(Point(5,0), Point(5,length), 0, 0, 0, display.color(50), ZP);
	lmask.line(Point(6,0), Point(6,length), 0, 0, 0, display.color(50), ZP);
	return(line, lmask);
}

drawstone(screen: ref Image, p: Point)
{
	center := Point(10,10);
#	sys->print("%d %d\n", p.x, p.y);
	if(first){
		(halo, mask) = mkstone();
		first=0;
	}
	p.x -= (p.x + delta/2) % delta;
	p.y -= (p.y + delta/2) % delta;
	screen.draw(Rect(p.sub(center),p.add(center)), halo, mask, ZP);
}

drawbackground(screen: ref Image)
{
	r := screen.r;
	
	y := r.dy();
	sys->print("y %d\n", y);
	d := y/24;
	
	nr := Rect(r.min, Point(r.max.x, r.min.y+d));
	for(i:=0; i < 24; i++){
		screen.draw(nr, display.rgb(0,0,255-(i*10)), nil, ZP);
		nr.min.y = nr.max.y;
		nr.max.y+= d;
	}
}
delta: int;

drawboard(screen: ref Image, t: int)
{
	if(screen == nil)
		return;
#	tms := daytime->local(t);
	r := screen.r;
#	r = r.inset(20);
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
#	rad /= 2;
#	rad -= 8;
#	sys->print("%d\n", rad);
	inc := rad / 9;
	delta = inc;

	drawbackground(screen);
	
	# vertical
	(vline, vmsk) := mkvline(256, 1);
	for(i:=0; i<8; i++){
		p0 := r.min;
		p1 := Point(r.min.x, r.min.y + (inc * 8));
		p0.x += inc * i;
		p1.x += inc * i;
#		sys->print("%d\n", p0.x);
#		screen.line(p0, p1, 0, 0, 0, display.white, ZP);
		screen.draw(Rect(p0, (p1.x+8, p1.y)), vline, vmsk, ZP);
	}
	
	#horizontal
	(line, msk) := mkhline(256, 1);
	for(i=0; i<8; i++){
		p0 := Point(r.min.x, r.min.y);
		p1 := Point(r.min.x + (inc * 8), r.min.y);
		p0.y += inc * i;
		p1.y += inc * i;
#		sys->print("%d\n", p0.y);
#		screen.line(p0, p1, 0, 0, 0, display.white, ZP);
		screen.draw(Rect(p0, (p1.x, p1.y+8)), line, msk, ZP);
	}


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
