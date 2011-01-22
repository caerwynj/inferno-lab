implement Board;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Screen, Image, Point, Rect, Font: import draw;
include "math.m";
	math: Math;
include "ir.m";
include "mux.m";
	mux: Mux;
include "frame.m";
	framem: Framem;
Frame, BACK, HIGH, BORD, TEXT, HTEXT, NCOL:import framem;

Board: module
{
	init:	fn(nil: ref Mux->Context, nil: list of string);
};

display: ref Display;
screen: ref Screen;
mainimage: ref Image;
mask: ref Image;
stone: ref Image;
ZP := Point(0, 0);
font: ref Font;
frame: ref Frame;
textcols : array of ref Draw->Image;
buf: string;
#offset := Point(0,15);
offset := Point(0,198+15);
chars := array[] of {
	array[] of {"Q", "U", "O", "N", "G", "Z", "?", "!", "*"},
	array[] of {"~", "B", "R", "D",  "I", "M", "X", "<-", " "},
	array[] of {"J", "V", "E", " ", "S", "P", ".", "->", "()", },
	array[] of {"[]", "'", "H", "T", "A", "L", "Y", "F", "-"},
	array[] of {"", "7", "8", "9", "W", "C", "K", "", ""},
	array[] of {"", "4", "5", "6", "", "", "", "", ""},
	array[] of {"0", "1", "2", "3", "", "", "", "", ""},
	array[] of {"", "", "", "", "", "", "", "", ""},
	array[] of {"", "", "", "", "", "", "", "", ""},
};
xwidth := 32;
ywidth := 24;

init(ctxt: ref Mux->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	mux = load Mux Mux->PATH;
	framem = load Framem Framem->PATH;
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	display = ctxt.display;
	screen = ctxt.screen;
	mainimage = screen.newwindow(screen.image.r, 0, 0);
	mainimage.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;
	font = Font.open(display, "/fonts/vera/Vera/Vera.14.font");
	textcols = array[NCOL] of ref Draw->Image;
#	textcols[BACK] = display.colormix(Draw->Paleyellow, Draw->White);
	textcols[BACK] = display.black;
	textcols[HIGH] = display.color(Draw->Darkyellow);
	textcols[BORD] = display.color(Draw->Yellowgreen);
#	textcols[TEXT] = display.black;
	textcols[TEXT] = display.color(Draw->Medgreen);
	textcols[HTEXT] = display.black;
	framem->init(ctxt);
	frame = framem->newframe();
	buf = "% ";

	last := Point(-1,-1);
	drawboard(mainimage);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			(x,y) := findrect(p.xy);
			np := Point(x,y);
			if(!np.eq(last)) {
				s := "";
#				sys->print("ptr %d %d: %d %d: %s\n", p.xy.x, p.xy.y, x, y, chars[y][x]);
				if(y >= 0 && y < len chars && x >= 0 && x < len chars[y]){
					s = chars[y][x];
					if(len s > 0){
						if(frame.lastlinefull){
							buf = buf[len buf / 2:];
							framem->frdelete(frame, 0, frame.nchars);
							framem->frinsert(frame, buf, len buf, frame.p0);
						}
						case s {
						"->" =>
							buf[len buf] = '\n';
							framem->frinsert(frame, buf[len buf - 1:], 1, frame.p0);
						"<-" =>
							if(frame.p1 > 0)
								framem->frdelete(frame, frame.p1-1, frame.p1);
						* =>
							buf[len buf] = s[0];
							framem->frinsert(frame, buf[len buf - 1:], 1, frame.p0);
						}
					}
				}
				op := Point(x*32, y*24);
				if(y%2)
					op.x -= 16;
					spawn animate(np, s);
#				if(p.xy.in(Rect(op,op.add(Point(30,24))).addpt(offset))){
#				}
			}
			last = np;
		}else
			last = Point(-1,-1);
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

findrect(p: Point): (int, int)
{
	y := (p.y - offset.y) / 24;
	if(y%2)
		x := (p.x - offset.x + 16) / 32;
	else
		x = (p.x - offset.x) / 32;
	return (x,y);
}

animate(sp: Point, s: string)
{	 
	k := 0;
	if(sp.y%2)
		xshift := -16;
	else
		xshift = 0;
	m := display.newimage(Rect((0,0),(30,30)), Draw->RGBA32, 0, Draw->Transparent);
	p := array[] of {Point(15,0+k), Point(30-k,8), Point(30-k,22),
		Point(15,30-k), Point(0+k,22), Point(0+k,8), Point(15,0+k)};
	m.poly(p, 0,0,1, display.color(255), ZP);
	off := Point(xwidth*sp.x + xshift, sp.y*ywidth);
#	mainimage.draw(mask.r.addpt(off).addpt(offset), display.color(Draw->Green), m, ZP);
	for(i := 0; i <= 10; i++){
		drawkey(sp.x, sp.y, 100 - (i*10), s);
		mainimage.flush(Draw->Flushnow);
		sys->sleep(100);
	}
}

mkstone() : ref Image
{
	center := Point(15,15);
	m := display.newimage(Rect((0,0),(30,30)), Draw->RGBA32, 0, Draw->Transparent);
	for(i:=0;i<10;i++)
		m.fillellipse(center, i,i,display.color(30-(i*2)), ZP);

	return m;
}

drawboard(s: ref Image)
{
	 if(s == nil)
		   return;
	 s.draw(s.r, display.black, nil, ZP);


	 mask = display.newimage(Rect((0,0),(30,30)), Draw->RGBA32, 0, Draw->Transparent);
	   for(k:=0; k < 15; k++){
		p := array[] of {Point(15,0+k), Point(30-k,8), Point(30-k,22),
			Point(15,30-k), Point(0+k,22), Point(0+k,8), Point(15,0+k)};
		mask.fillpoly(p, 0, display.color(50+ (k*2)), ZP);
	  }
	 stone = mkstone();
	 blue := 255;
	 xshift := 0;
	 for (j := 0; j < 7; j++) {
		  for(i := 0; i < 9; i++) {
				 off := Point(xwidth*i + xshift, j*ywidth);
				 s.draw(mask.r.addpt(off).addpt(offset), display.rgb(100,100,blue), mask, ZP);
				 blue -= 2;
				 s.draw(stone.r.addpt(off).addpt(offset), display.white, stone, ZP);
				 m := font.width(chars[j][i]);
				 m = (12 - m + 1) / 2;
				 s.text(offset.add(off).add((9+m,8)), display.black, ZP,font, chars[j][i]);
		   }
		   if(!xshift)
				 xshift = - (16);
		   else
				 xshift = 0;
	 }
	 
	s.draw(Rect((0,0),(256,198)), textcols[BACK], nil, ZP);
	framem->frclear(frame, 0);
	framem->frinit(frame, Rect((0,0),(256,198)),  font, s, textcols);
	framem->frinsert(frame, buf, len buf, 0);
	framem->frdrawsel(frame, (0,0), 0, len buf, 0);

	 s.flush(Draw->Flushnow);
}

drawkey(x,y,intensity: int, s: string)
{
	blue := 255;
	blue -= 2 * (x+1) * (y+1);
	xshift := 0;
	if(y%2)
		xshift = -16;
	off := Point(xwidth*x + xshift, y*ywidth);
	k := 0;
	p := array[] of {Point(15,0+k), Point(30-k,8), Point(30-k,22),
			Point(15,30-k), Point(0+k,22), Point(0+k,8), Point(15,0+k)};
	for(i:=0;i<len p; i++)
		p[i] = p[i].add(off).add(offset);
	mainimage.fillpoly(p, 0, display.black, ZP);
	mainimage.draw(mask.r.addpt(off).addpt(offset), display.rgb(100 + intensity,100,blue), mask, ZP);
	mainimage.draw(stone.r.addpt(off).addpt(offset), display.white, stone, ZP);
	m := font.width(s);
	m = (12 - m +1) / 2;
	mainimage.text(offset.add(off).add((9+m,8)), display.black, ZP,font, s);
}

