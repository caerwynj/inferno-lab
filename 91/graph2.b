implement Graph;

include "common.m";
include "freetype.m";
freetype: Freetype;
Matrix, Face: import freetype;

sys : Sys;
drawm : Draw;
dat : Dat;
gui : Gui;
utils : Utils;

Image, Point, Rect, Font, Display : import drawm;
black, white, display : import gui;
error : import utils;

refp : ref Point;
pixarr : array of byte;
face: ref Face;
glyphsimg : ref Image;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	drawm = mods.draw;
	dat = mods.dat;
	gui = mods.gui;
	utils = mods.utils;
	freetype = load Freetype Freetype->PATH;
	face = freetype->newface("/fonts/DejaVuSans.ttf", 0);
	face.setcharsize(14<<6, 72, 72);
	glyphsimg = display.newimage(Rect((0,0), (20,20)), Draw->GREY8, 0, Draw->Black);

	refp = ref Point;
	refp.x = refp.y = 0;
}

stringx(d : ref Image, p : Point, f : ref Font, s : string, c : ref Image)
{
	f.height = face.height;
	bbox := Rect((0,0), (0,0));
	origin := Point(p.x<<6, (p.y+face.ascent)<<6);
	for (i := 0; i < len s; i++)
	{
		g := face.loadglyph(s[i]);
		if (g == nil){
			sys->print("No glyph for char [%c]\n", s[i]);
			continue;
		}

		drawpt := Point((origin.x>>6)+g.left, (origin.y>>6)-g.top);
		r := Rect((0,0), (g.width, g.height));
		r = r.addpt(drawpt);
		bbox = bbox.combine(r);
		glyphsimg.writepixels(Rect((0,0), (g.width, g.height)), g.bitmap);
		d.draw(r, c, glyphsimg, (0,0));
		origin.x += g.advance.x;
#		origin.y -= g.advance.y;
#		sys->print("g.width=%d, g.height=%d, g.advance.x=%d, g.top=%d, g.left=%d\n", 
#			g.width, g.height, g.advance.x, g.top, g.left);
	}
}

charwidth(f : ref Font, c : int) : int
{
	f.height = face.height;
	g := face.loadglyph(c);
	return g.advance.x >> 6;
}

strwidth(f : ref Font, s : string) : int
{
	f.height = face.height;
	origin := Point(0,0);
	for (i := 0; i < len s; i++)
	{
		g := face.loadglyph(s[i]);
		if (g == nil){
			sys->print("No glyph for char [%c]\n", s[i]);
			continue;
		}
		origin.x += g.advance.x;
		origin.y -= g.advance.y;
	}
	return origin.x >> 6;
}

charwidthx(f : ref Font, c : int) : int
{
	s : string = "z";

	s[0] = c;
	return f.width(s);
}

strwidthx(f : ref Font, s : string) : int
{
	return f.width(s);
}

balloc(r : Rect, c : Draw->Chans, col : int) : ref Image
{
	im := display.newimage(r, c, 0, col);
	if (im == nil)
		error("failed to get new image");
	return im;
}

draw(d : ref Image, r : Rect, s : ref Image, m : ref Image, p : Point)
{
	d.draw(r, s, m, p);
}

stringxx(d : ref Image, p : Point, f : ref Font, s : string, c : ref Image)
{
	d.text(p, c, (0, 0), f, s);
}

cursorset(p : Point)
{
	gui->cursorset(p);
}

cursorswitch(c : ref Dat->Cursor)
{
	gui->cursorswitch(c);
}

binit()
{
}

bflush()
{
}

berror(s : string)
{
	error(s);
}
