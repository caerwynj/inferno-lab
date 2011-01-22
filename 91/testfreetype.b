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

MINPTS: con 10;
MAXPTS: con 180;
FRAMETIME: con 50;

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	sys->pctl(Sys->NEWPGRP, nil);

	if (len args != 3) {
		sys->print("usage: path msg\n");
		return;
	}

	draw := load Draw Draw->PATH;
	Point, Rect, Image, Display, Screen: import draw;
	wmc = load Wmclient Wmclient->PATH;
	if (wmc == nil) {
		sys->print("cannot load wmclient: %r\n");
		raise "fail:init";
	}
	wmc->init();

	args = tl args;
	path := hd args;
	args = tl args;
	msg := hd args;

	ft := load Freetype Freetype->PATH;
	Matrix, Face: import ft;
	if (ft == nil) {
		sys->print("failed to load %s:%r\n", Freetype->PATH);
		return;
	}
	face := ft->newface(path, 0);
	if (face == nil) {
		sys->print("failed to get face:%r\n");
		return;
	}

	win := wmc->window(ctxt, "Infernal Text", 0);
	if (win == nil) {
		sys->print("failed to create window\n");
		return;
	}

	bgimg := win.display.open("/icons/inferno.bit");
	fgimg := win.display.color(int 16r8f8f8f8f);
	bgr: Rect;

	if (bgimg != nil)
		bgr = bgimg.r;
	else {
		bgimg = win.display.white;
		bgr = Rect((0,0),(400,400));
	}
	midx := bgr.dx()/2;
	midy := bgr.dy()/2;

	if (fgimg == nil)
		fgimg = win.display.white;
	if (fgimg == nil || bgimg == nil)
		return;
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

	qtrpts := 4*MINPTS;
	step := 4;

	prevbbox := bgr;
	win.image.drawop(prevbbox.addpt(win.image.r.min), bgimg, nil, bgr.min, Draw->S);
	bufimg.drawop(prevbbox, bgimg, nil, bgr.min, Draw->S);
	for (angle := 0; ; angle += 2) {
		then := sys->millisec();
		bbox := Rect((midx, midy), (midx, midy));
		c := cos(angle);
		s := sin(angle);
		m := ref Matrix(c, -s, s, c);
		face.setcharsize(qtrpts<<4, 76, 76);
		face.settransform(m, nil);
		qtrpts += step;
		if (qtrpts > 4*MAXPTS || qtrpts < 4*MINPTS)
			step = -step;
		winim := win.image;
		if (winim != nil) {
			bufimg.drawop(prevbbox, bgimg, nil, prevbbox.min, Draw->S);
			origin := Point(midx+(50*c-50*s>>16)<<6, midy+(50*s+50*c>>16)<<6);

			Renderloop:
			for (i := 0; i < len msg; i++) {
				g := face.loadglyph(msg[i]);
				if (g == nil)
					continue;
				drawpt := Point(g.left+(origin.x>>6), (origin.y>>6)-g.top);
				r := Rect((0,0), (g.width, g.height));
				r = r.addpt(drawpt);
				if (!r.Xrect(bgr))
					break Renderloop;
				bbox = bbox.combine(r);
				img.writepixels(r, g.bitmap);
				bufimg.draw(r, fgimg, img, r.min);
				origin.x += g.advance.x;
				origin.y -= g.advance.y;
			}
			updater := prevbbox.combine(bbox);
			winim.drawop(updater.addpt(winim.r.min), bufimg, nil, updater.min, Draw->S);
			prevbbox = bbox;
			winim = nil;
		}
		now := sys->millisec();
		wait := FRAMETIME - (now-then);
		if (wait > 0)
			sys->sleep(wait);
	}
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

sin(deg: int): int
{
	mul := 1;
	deg %= 360;
	if (deg < 0)
		deg = 360 + deg;
	if (deg >= 180) {
		mul = -1;
		deg -= 180;
	}
	if (deg >= 90)
		deg = 90 - (deg-90);
	return mul*sin90[deg];
}

cos(deg:int): int
{
	return sin(deg+90);
}

sin90 := array[] of {
	0, 1143, 2287, 3429, 4571, 5711, 6850, 7986, 9120, 10252,
	11380, 12504, 13625, 14742, 15854, 16961, 18064, 19160, 20251, 21336,
	22414, 23486, 24550, 25606, 26655, 27696, 28729, 29752, 30767, 31772,
	32767, 33753, 34728, 35693, 36647, 37589, 38521, 39440, 40347, 41243,
	42125, 42995, 43852, 44695, 45525, 46340, 47142, 47929, 48702, 49460,
	50203, 50931, 51643, 52339, 53019, 53683, 54331, 54963, 55577, 56175,
	56755, 57319, 57864, 58393, 58903, 59395, 59870, 60326, 60763, 61183,
	61583, 61965, 62328, 62672, 62997, 63302, 63589, 63856, 64103, 64331,
	64540, 64729, 64898, 65047, 65176, 65286, 65376, 65446, 65496, 65526,
	65536
};

