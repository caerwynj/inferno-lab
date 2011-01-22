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

	background = drawbackground();
	dots = drawgrid1();
	background.draw(background.r, dots, nil, ZP);
	anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
	animmask = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);

	drawboard(mainimage.r);
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


mkhline(length, thick: int) : (ref Image, ref Image)
{
	line := display.newimage(Rect((0,0), (length, 8)),  Draw->RGBA32, 0, Draw->White);
	lmask := display.newimage(Rect((0,0),(length, 8)), Draw->RGBA32, 0, Draw->Transparent);

	lmask.draw(Rect((0,0), (length, 8)), display.color(75), nil, ZP);
	lmask.line(Point(0,2), Point(length, 2), 0, 0, 1, display.color(100), ZP);
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
	offset := Point(40,10);
	for(i := 0; i < 8; i++){   # horizontal
		for(j :=0; j < 8; j++){	# vertical
		 	p := Point(i*22, j*22);
		 	col := display.white;
		 	if((i+j)%2)
			col = display.color(Draw->Red);
			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), col, mask, ZP);
		}
	}
	return layer;
}

drawgrid(): ref Image
{
	r := mainimage.r;
	if(r.dx() < r.dy())
		rad := r.dx();
	else
		rad = r.dy();
	inc := rad / 9;
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
	
	(line, msk) := mkhline(256, 1);

	for(i := 0; i < 6; i++){   # horizontal
		p0 := Point(r.min.x, r.min.y);
		p1 := Point(r.min.x + (inc * 8), r.min.y);
		p0.y += inc * i;
		p1.y += inc * i;
		layer.draw(Rect(p0, (p1.x, p1.y+8)), line, msk, ZP);
	}
	
	
	(vline, vmsk) := mkvline(256, 1);
	
	for(j := 0; j < 6; j++) { # vertical
		p0 := r.min;
		p1 := Point(r.min.x, r.min.y + (inc * 8));
		p0.x += inc * j;
		p1.x += inc * j;
		layer.draw(Rect(p0, (p1.x+8, p1.y)), vline, vmsk, ZP);
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
	mainimage.draw(r, background, nil, r.min);
#	mainimage.draw(r, dots, nil, r.min);
	mainimage.draw(r, anim, animmask, r.min);
	mainimage.flush(Draw->Flushnow);
}
