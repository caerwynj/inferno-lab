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
	screen.image.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;

	background = drawbackground();
	dots = drawdots();
	background.draw(background.r, dots, nil, ZP);
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
#	for(i=0;i<10;i++){
#		animmask.fillellipse(p, 2+i, 2+i, display.color(200), ZP);
#		drawboard(r);
#		sys->sleep(40);
#	}
#	animmask.draw(r, display.opaque, display.transparent, ZP);
#	animmask.draw(r, display.color(10), nil, ZP);
#	anim.draw(r, display.transparent, nil, ZP);
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


drawbackground(): ref Image
{
	bg := display.newimage(display.image.r, Draw->RGBA32, 0, Draw->White);
	r := bg.r;
	y := r.dy();
	d := y/48;
	
	for(i:=0; i < 48; i++){
		bg.ellipse(Point(r.dx()/2, r.dy()/2), i*4, i*4, 2, display.rgb(0,0,255-(i*5)), ZP);
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
