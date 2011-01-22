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
offset := Point(0,15);
chars := array[] of {
	array[] of {"Q", "U", "O", "N", "G", "Z", "?", "!", "*"},
	array[] of {"~", "B", "R", "D",  "I", "M", "X", " ", " "},
	array[] of {"J", "V", "E", " ", "S", "P", ".", "", "()", },
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
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	display = ctxt.display;
	screen = ctxt.screen;
	mainimage = screen.newwindow(screen.image.r, 0, 0);
	mainimage.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;
	font = Font.open(display, "/fonts/vera/Vera/Vera.14.font");

	last := Point(-1,-1);
	drawboard(mainimage);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			(x,y) := findrect(p.xy);
			np := Point(x,y);
			if(!np.eq(last)) {
#				sys->print("ptr %d %d: %d %d: %s\n", p.xy.x, p.xy.y, x, y, chars[y][x]);
				op := Point(x*32, y*24);
				if(y%2)
					op.x -= 16;
					spawn animate(np);
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

animate(sp: Point)
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
	blue := 255;
	blue -= 2 * (sp.x+1) * (sp.y+1);
#	for(i := 0; i <= 10; i++){
#		drawkey(sp.x, sp.y, display.rgb(100 + 100 - (i*10),100,blue));
#		mainimage.flush(Draw->Flushnow);
#		sys->sleep(100);
#	}
	while(blue>0){
		drawkey(sp.x, sp.y, display.rgb(blue, blue, blue));
		mainimage.flush(Draw->Flushnow);
		sys->sleep(100);
		blue -=10;
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
	 for (j := 0; j < 15; j++) {
		  for(i := 0; i < 9; i++) {
				 off := Point(xwidth*i + xshift, j*ywidth);
#				 s.draw(mask.r.addpt(off).addpt(offset), display.rgb(100,100,blue), mask, ZP);
				 blue -= 2;
				 s.draw(stone.r.addpt(off).addpt(offset), display.white, stone, ZP);
#				 m := font.width(chars[j][i]);
#				 m = (12 - m + 1) / 2;
#				 s.text(offset.add(off).add((9+m,8)), display.black, ZP,font, chars[j][i]);
		   }
		   if(!xshift)
				 xshift = - (16);
		   else
				 xshift = 0;
	 }

	 s.flush(Draw->Flushnow);
}

drawkey(x,y: int, color: ref Image)
{
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
	mainimage.draw(mask.r.addpt(off).addpt(offset), color, mask, ZP);
	mainimage.draw(stone.r.addpt(off).addpt(offset), display.white, stone, ZP);
#	m := font.width(chars[y][x]);
#	m = (12 - m +1) / 2;
#	mainimage.text(offset.add(off).add((9+m,8)), display.black, ZP,font, chars[y][x]);
}

