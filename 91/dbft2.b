#
#	This is an example user of libfreetye, based on the example
#	from chris@vitanuova.com (see below) -- phillip
#
#	From: 	  chris@vitanuova.com
#	Subject: 	Re: Freetype
#	Date: 	June 23, 2003 5:37:14 AM EDT
#	To: 	  inferno@topica.com
#	Reply-To: 	  inferno@topica.com
#
#Haven't written the man pages yet.
#
#Here is a sample prog to help you along.
#Note: this is not a good example of how to work with the new wm,
#it is just hacked up as a test for freetype.
#
#You'll also need to source your own ttf or type 1 fonts from somewhere.
#Try www.nongnu.org/freefont for ttf or the Ghostscript type1 fonts.
#
#Chris.

implement TestFreetype;

include "sys.m";
include "draw.m";
include "tk.m";
include "wmclient.m";
include "freetype.m";

TestFreetype: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

sys: Sys;
wmc: Wmclient;
Window: import wmc;

MINPTS: con 64;
MAXPTS: con 180;
FRAMETIME: con 30;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);


	draw := load Draw Draw->PATH;
	Point, Rect, Image, Display, Screen: import draw;
	wmc = load Wmclient Wmclient->PATH;
	if (wmc == nil) {
		sys->print("cannot load wmclient: %r\n");
		raise "fail:init";
	}
	wmc->init();

	ft := load Freetype Freetype->PATH;
	Matrix, Face: import ft;
	if (ft == nil) {
		sys->print("failed to load %s:%r\n", Freetype->PATH);
		return;
	}
	face := ft->newface("./fonts/DejaVuSans-Bold.ttf", 0);
	if (face == nil) {
		sys->print("failed to get face:%r\n");
		return;
	}

	win := wmc->window(ctxt, "", 0);
	if (win == nil) {
		sys->print("failed to create window\n");
		return;
	}


	bgimg := win.display.black;
	bgr := Rect((0,0),(600,400));
	fgimg := win.display.white;

	img := win.display.newimage(bgr, Draw->GREY8, 0, Draw->White);
	if (img == nil)
		return;

	spawn handler(win);
	win.reshape(bgr);
	win.onscreen("place");
	if (win.image == nil)
		return;

	# can we get win.image.chans any earlier?
	bufimg := win.display.newimage(bgr, win.image.chans, 0, Draw->White);
	if (bufimg == nil)
		killme();

	img = win.image;
	s := "abcdefghij";
	origin := Point(img.r.min.x<<6, img.r.min.add((0, 100)).y<<6);
	txtimg := fgimg;
	bbox := Rect((0,0), (0,0));

	#	The rendered glyph bitmap from ft2 is a 256-grey image
	glyphsimg	:= img.display.newimage(img.r, Draw->GREY8, 0, Draw->Black);
	xbufimg		:= img.display.newimage(img.r, img.chans, 0, Draw->Black);
	if (glyphsimg == nil || xbufimg == nil)
	{
		raise "fail: Couldn't alloc glyphsimg/bufimg for rendering via FT2 in Pgui";
	}

	face.setcharsize(14<<6, 96, 96);
	for (i := 0; i < len s; i++)
	{
		g := face.loadglyph(s[i]);
		if (g == nil)
		{
			sys->print("No glyph for char [%c]\n", s[i]);
			continue;
		}

		drawpt := Point(g.left+(origin.x>>6), (origin.y>>6)-g.top);
		r := Rect((0,0), (g.width, g.height));
		r = r.addpt(drawpt);
		bbox = bbox.combine(r);
		glyphsimg.writepixels(r, g.bitmap);
		xbufimg.draw(r, txtimg, glyphsimg, r.min);
		origin.x += g.advance.x;
		origin.y -= g.advance.y;

sys->print("g.with=%d, g.height=%d, g.advance.x=%d\n", g.width, g.height, g.advance.x);
	}

	img.drawop(img.r, xbufimg, nil, img.r.min, Draw->S);

	for (;;) ;
}

handler(win: ref Wmclient->Window)
{
	win.startinput("ptr"::nil);
	for(;;) alt{
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		if (e == "exit")
			killme();
		win.wmctl(e);
	p := <-win.ctxt.ptr =>
		win.pointer(*p);
	}
}

killme()
{
	pid := sys->pctl(0, nil);
	sys->fprint(sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE), "killgrp");
	exit;
}
