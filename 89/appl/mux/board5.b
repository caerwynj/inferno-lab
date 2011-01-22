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
dots: ref Image;
anim: ref Image;
animmask: ref Image;
background: ref Image;
mainimage: ref Image;

ZP := Point(0, 0);
first:=1;
textfont: ref Font;

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
	textfont = Font.open(display, "/fonts/10646/9x15/9x15.font");

	drawboard(mainimage.r);
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

mkvline() : ref Image
{
	lmask := display.newimage(Rect((0,0),(9, 1)), Draw->RGBA32, 1, Draw->Transparent);
	
	lmask.draw(Rect((0,0),(1,1)), display.color(10), nil, ZP);
	lmask.draw(Rect((1,0),(2,1)), display.color(40), nil, ZP);
	lmask.draw(Rect((2,0),(3,1)), display.color(60), nil, ZP);
	lmask.draw(Rect((3,0),(4,1)), display.color(80), nil, ZP);
	lmask.draw(Rect((4,0),(5,1)), display.color(200), nil, ZP);
	lmask.draw(Rect((5,0),(6,1)), display.color(80), nil, ZP);
	lmask.draw(Rect((6,0),(7,1)), display.color(60), nil, ZP);
	lmask.draw(Rect((7,0),(8,1)), display.color(40), nil, ZP);
	lmask.draw(Rect((8,0),(9,1)), display.color(10), nil, ZP);
	return lmask;
}

drawdots(): ref Image
{
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
	(dot, mask) := mkstone();
	offset := Point(18,10);
	for(i := 0; i < 6; i++){   # horizontal
		for(j :=0; j < 6; j++){	# vertical
		 	p := Point(i*40, j*30);
			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), dot, mask, ZP);
		}
	}
	return layer;
}


drawpieces(): ref Image
{
	red := display.color(Draw->Red);
	pieces := array[8] of {
#		array[] of	{"♖", "♘", "♗", "♕", "♔", "♗", "♘", "♖"},
#		array[] of	{"♙", "♙", "♙", "♙", "♙", "♙", "♙", "♙"},
		array[] of	{"♜", "♞", "♝", "♛", "♚", "♝", "♞", "♜"},
		array[] of	{"♟", "♟", "♟", "♟", "♟", "♟", "♟", "♟"},
		array[] of	{"", "", "", "", "", "", "", ""},
		array[] of	{"", "", "", "", "", "", "", ""},
		array[] of	{"", "", "", "", "", "", "", ""},
		array[] of	{"", "", "", "", "", "", "", ""},
		array[] of	{"♟", "♟", "♟", "♟", "♟", "♟", "♟", "♟"},
		array[] of	{"♜", "♞", "♝", "♛", "♚", "♝", "♞", "♜"},
	};
	
	for(i := 0; i < 8; i++){   # horizontal
		for(j :=0; j < 8; j++){	# vertical
		 	p := Point(i*21, j*21);
			offset := Point(50,18);
		 	if(j < 3)
		 		col := red;
		 	else
		 		col = display.white;
		 	if(j == 1 || j == 6)
		 		offset.x += 1;
		 	mainimage.text(p.add(offset), col, ZP,  textfont, pieces[j][i]);
		}
	}
	return mainimage;
}

drawgrid(): ref Image
{
	offset := Point(40,10);
	r := Rect((0,0),(256,192));
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
	inc := rad / 9;
	
	msk := mkhline();

	for(i := 0; i < 9; i++){   # horizontal
		p0 := Point(r.min.x, r.min.y);
		p1 := Point(177, r.min.y);
		p0.y += inc * i;
		p1.y += inc * i;
		mainimage.draw(Rect(p0, (p1.x, p1.y + msk.r.dy())).addpt(offset), display.white, msk, ZP);
	}
	
	
	vmsk := mkvline();
	
	for(j := 0; j < 9; j++) { # vertical
		p0 := r.min;
		p1 := Point(r.min.x, 177);
		p0.x += inc * j;
		p1.x += inc * j;
		mainimage.draw(Rect(p0, (p1.x+vmsk.r.dx(), p1.y)).addpt(offset), display.white, vmsk, ZP);
	}
	return mainimage;
}


drawbackground(): ref Image
{
	r := mainimage.r;
	y := r.dy();
	d := y/48;
	
	nr := Rect(r.min, Point(r.max.x, r.min.y+d));
	for(i:=0; i < 48; i++){
		mainimage.draw(nr, display.rgb(0,0,0+(i*5)), nil, ZP);
		nr.min.y = nr.max.y;
		nr.max.y+= d;
		}
	return mainimage;
}

#combine all the layers
drawboard(nil: Rect)
{
	drawbackground();
	drawgrid();
	drawpieces();
	mainimage.flush(Draw->Flushnow);
}
