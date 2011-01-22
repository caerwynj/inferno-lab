implement Nds;

include "sys.m";
	sys: Sys;
include "draw.m";
draw: Draw;
Display, Rect, Point, Image, Font, Screen: import draw;
include "mux.m";
	mux: Mux;
	Context: import mux;
include "nds.m";

ZP := Point(0, 0);

init(ctxt: ref Mux->Context)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
}

background(display: ref Display): ref Image
{
	bg := display.newimage(display.image.r, Draw->RGBA32, 0, Draw->White);
	r := bg.r;
	y := r.dy();
	d := y/24;
	
	nr := Rect(r.min, Point(r.max.x, r.min.y+d));
	for(i:=0; i < 24; i++){
		bg.draw(nr, display.rgb(0,0,255-(i*10)), nil, ZP);
		nr.min.y = nr.max.y;
		nr.max.y+= d;
	}
	return bg;
}
