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
	screen.image.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;
	textfont = Font.open(display, "/fonts/10646/9x15/9x15.font");

	background = drawbackground();
	dots = drawgrid();
	background.draw(background.r, dots, nil, ZP);
#	background.draw(background.r, drawgrid1(), nil, ZP);
	background.draw(background.r, drawgrid2(), nil, ZP);
	anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
	animmask = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);

	drawboard(screen.image.r);
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			sys->print("ptr %d %d\n", p.xy.x, p.xy.y);
			spawn animate(p.xy);
		}
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

animate(p: Point)
{
	red := display.color(Draw->Red);
	trans0 := display.color(180);
	trans1 := display.color(75);
	trans2 := display.color(50);
	trans3 := display.color(30);
	r := Rect(p.sub(Point(20,20)), p.add(Point(20,20)));
	animmask.draw(r, display.opaque, nil, ZP);
	for(i:=2;i<10;i++){
		animmask = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
		animmask.ellipse(p, 2*i, 2*i, 0, trans0, ZP);
		animmask.ellipse(p, 2*(i-1), 2*(i-1), 1, trans1, ZP);
		animmask.ellipse(p, 2*(i-2), 2*(i-2), 1, trans2, ZP);
		animmask.ellipse(p, 2*(i-3), 2*(i-3), 1, trans3, ZP);
		anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
		anim.ellipse(p, 2*i, 2*i, 0, display.white, ZP);
		anim.ellipse(p, 2*(i-1), 2*(i-1), 1, display.white, ZP);
		anim.ellipse(p, 2*(i-2), 2*(i-2), 1, display.white, ZP);
		drawboard(r);
		sys->sleep(40);
	}
	sys->sleep(40);
	anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
	drawboard(r);
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

mksquare(): ref Image
{
	r := Rect((0,0),(20,20));
	mask := display.newimage(r, Draw->RGBA32, 0, Draw->Transparent);
	
	for(i := 0; i < 10; i++)
		mask.draw(r.inset(i), display.color(10 + i*10), nil, ZP);
	
	mask.draw(r.inset(10), display.color(255), nil, ZP);
	return mask;
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
	center := Point(10,10);
	offset := Point(18,10);
	for(i := 0; i < 6; i++){   # horizontal
		for(j :=0; j < 6; j++){	# vertical
		 	p := Point(i*40, j*30);
			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), dot, mask, ZP);
		}
	}
	return layer;
}

drawgrid1(): ref Image
{
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
#	(dot, mask) := mkstone();
	mask := mksquare();
	center := Point(10,10);
	offset := Point(45,15);
	for(i := 0; i < 8; i++){   # horizontal
		for(j :=0; j < 8; j++){	# vertical
		 	p := Point(i*21, j*21);
		 	col := display.white;
		 	if((i+j)%2)
			col = display.color(Draw->Red);
			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), col, mask, ZP);
		}
	}
	return layer;
}

drawgrid2(): ref Image
{
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
#	(dot, mask) := mkstone();
	mask := mksquare();
	center := Point(10,10);
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
		 		col := display.color(Draw->Red);
		 	else
		 		col = display.white;
		 	if(j == 1 || j == 6)
		 		offset.x += 1;
		 	layer.text(p.add(offset), col, ZP,  textfont, pieces[j][i]);
#			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), col, mask, ZP);
		}
	}
	return layer;
}

drawgrid(): ref Image
{
	offset := Point(40,10);
	r := screen.image.r;
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
	inc := rad / 9;
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
	
	msk := mkhline();

	for(i := 0; i < 9; i++){   # horizontal
		p0 := Point(r.min.x, r.min.y);
		p1 := Point(177, r.min.y);
		p0.y += inc * i;
		p1.y += inc * i;
		layer.draw(Rect(p0, (p1.x, p1.y + msk.r.dy())).addpt(offset), display.white, msk, ZP);
	}
	
	
	vmsk := mkvline();
	
	for(j := 0; j < 9; j++) { # vertical
		p0 := r.min;
		p1 := Point(r.min.x, 177);
		p0.x += inc * j;
		p1.x += inc * j;
		layer.draw(Rect(p0, (p1.x+vmsk.r.dx(), p1.y)).addpt(offset), display.white, vmsk, ZP);
	}
	return layer;
}


drawbackground(): ref Image
{
	bg := display.newimage(display.image.r, Draw->RGBA32, 0, Draw->White);
	r := bg.r;
	y := r.dy();
	d := y/48;
	
	nr := Rect(r.min, Point(r.max.x, r.min.y+d));
	for(i:=0; i < 48; i++){
		bg.draw(nr, display.rgb(0,0,0+(i*5)), nil, ZP);
		nr.min.y = nr.max.y;
		nr.max.y+= d;
		}
	return bg;
}

#combine all the layers
drawboard(r: Rect)
{
	screen.image.draw(r, background, nil, r.min);
#	screen.image.draw(r, dots, nil, r.min);
	screen.image.draw(r, anim, animmask, r.min);
	screen.image.flush(Draw->Flushnow);
}
