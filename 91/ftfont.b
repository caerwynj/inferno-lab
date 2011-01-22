implement Ftfont;

include "sys.m";
sys:Sys;
include "draw.m";
draw: Draw;
Point, Rect, Image, Display: import draw;

include "freetype.m";
freetype: Freetype;
Face, Glyph: import freetype;
include "ftfont.m";

Font.open(d: ref Draw->Display, name: string, size: int): ref Font
{
	if(draw == nil){
		draw = load Draw Draw->PATH;
		sys = load Sys Sys->PATH;
		freetype = load Freetype Freetype->PATH;
	}
	font := ref Font(name, 0, 0, d, nil);
	font.face = freetype->newface(name, 0);
	font.face.setcharsize(size<<6, 72, 72);
	font.height = font.face.height;
	font.ascent = font.face.ascent;
	return font;
}

Font.build(d: ref Draw->Display, name, desc: string): ref Font
{
	return ref Font(name, 0, 0, nil, nil);
}

Font.width(f: self ref Font, str: string): int
{
	origin := Point(0,0);
	for (i := 0; i < len str; i++)
	{
		g := f.face.loadglyph(str[i]);
		if (g == nil){
			sys->print("No glyph for char [%c]\n", str[i]);
			continue;
		}
		origin.x += g.advance.x;
	}
	return origin.x >> 6;
}

Font.bbox(f: self ref Font, s: string): Rect
{
	bbox := Rect((0,0), (0,0));
	origin := Point(0,0);
	for (i := 0; i < len s; i++)
	{
		g := f.face.loadglyph(s[i]);
		if (g == nil){
			sys->print("No glyph for char [%c]\n", s[i]);
			continue;
		}

		drawpt := Point(g.left+(origin.x>>6), (origin.y>>6)-g.top);
		r := Rect((0,0), (g.width, g.height));
		r = r.addpt(drawpt);
		r = r.addpt((0,f.height));
		bbox = bbox.combine(r);
		origin.x += g.advance.x;
		origin.y -= g.advance.y;
	}
	return bbox;
}

Font.stringx(f : self ref Font, d : ref Draw->Image, p : Draw->Point, s : string, c : ref Draw->Image)
{
	glyphsimg := f.display.newimage(Rect((0,0), (20,20)), Draw->GREY8, 0, Draw->Black);
	origin := Point(p.x<<6, (p.y+f.face.ascent)<<6);
	for (i := 0; i < len s; i++)
	{
		g := f.face.loadglyph(s[i]);
		if (g == nil){
			sys->print("No glyph for char [%c]\n", s[i]);
			continue;
		}
		drawpt := Point((origin.x>>6)+g.left, (origin.y>>6)-g.top);
		r := Rect((0,0), (g.width, g.height));
		r = r.addpt(drawpt);
		glyphsimg.writepixels(Rect((0,0), (g.width, g.height)), g.bitmap);
		d.draw(r, c, glyphsimg, (0,0));
		origin.x += g.advance.x;
	}
}
