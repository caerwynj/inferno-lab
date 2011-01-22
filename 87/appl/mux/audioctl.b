implement Audioctl;

include "sys.m";
sys: Sys;
print, sprint: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;

include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

Audioctl: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
zr := ((0,0),(0,0));

ev: ref Element;

ones, zeros, black, white, blue, red, yellow, green: ref Image;

Ctl: adt {
	name:	string;
	devnam:	string;
	value:	int;
};

ctltab := array[20] of { Ctl
	("Volume Output", "audio out", 0),
	("Volume Synth", "synth", 0),
	("Volume CD", "cd", 0),
	("Volume Line", "line", 0),
	("Volume Mic", "mic", 0),
	("Volume Speaker", "speaker out", 0),
	("Treble", "treb out", 0),
	("Bass", "bass out", 0),
	("", "", 0)
};

status(ac: ref Iobuf)
{
	ac.seek(big 0, 0);
	while ((s := ac.gets('\n')) != nil) {
		print("%s", s);
	}
}

init(ctxt: ref Context, nil: list of string)
{
	key: int;
	e: ref Element;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;
	if ((bufio = load Bufio Bufio->PATH) == nil) {
		sys->print("Audioctl: Can't load bufio\n");
		exit;
	}

	if ((ac := bufio->open("/dev/volume", bufio->ORDWR)) == nil) {
		sys->print("Audioctl: Can't open /dev/volume: %r\n");
		exit;
	}
	while ((s := ac.gets('\n')) != nil) {
		sp := -1;
		for (i := 0; i < len s; i++) if (s[i] == ' ') sp = i;
		if (sp <= 1) {
			sys->print("Audioctl: /dev/volume bad:\n%s\n", s);
			exit;
		}
		for (i = 0; i < len ctltab && ctltab[i].name != nil; i++) {
			if (ctltab[i].devnam == s[0:sp]) {
				ctltab[i].value = int s[sp+1:];
				print("%s: %d\n",
					ctltab[i].devnam, ctltab[i].value);
			}
		}
	}

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;

	ones = display.color(draw->White);
	zeros = display.color(draw->Black);
	black = display.color(draw->Black);
	white = display.color(draw->White);
	blue = display.color(16rf4);
	red = display.color(draw->Red);
	yellow = display.color(draw->Yellow);
	green = display.color(draw->Green);

	textfont := Font.open(display, "*default*");

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->White),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->Red));		# highlightcolor

	env = ref Environ (ctxt.screen, style);

	ctxt.ctomux <-= Mux->AMstartir;
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	et := Element.text(env, "Audio Control", zr, Prefab->EText);

	ev = Element.elist(env, nil, Prefab->EVertical);

	for (i := 0; i < len ctltab; i++) {
		if (ctltab[i].name == "") break;
		eh := Element.elist(env, nil, Prefab->EHorizontal);
		eh.append(Element.separator(env, ((0,0),(10,1)), zeros, zeros));
		eh.append(Element.text(env, sprint("%d", ctltab[i].value),
			((0,0),(80,20)), Prefab->EText));
		eh.append(slider(env, ctltab[i].value));
		eh.append(Element.separator(env, ((0,0),(10,1)), zeros, zeros));
		eh.append(Element.text(env, ctltab[i].name, zr, Prefab->EText));
		eh.append(Element.separator(env, ((0,0),(10,1)), zeros, zeros));
		eh.adjust(Prefab->Adjpack, Prefab->Adjleft);
		eh.tag = ctltab[i].name;
		ev.append(Element.separator(env, ((0,0),(1,10)), zeros, zeros));
		ev.append(eh);
	}
	ev.append(Element.separator(env, ((0,0),(10,10)), zeros, zeros));
	ev.adjust(Prefab->Adjpack, Prefab->Adjup);

	c := Compound.box(env, Point(50, 50), et, ev);
	c.draw();

	windows[1] = c.image;

	n := 0;
	for(;;) {
		(key, n, e) = c.select(c.contents, n, ctxt.cir);
		case key {
		Ir->Select =>
			print("Select %d %s\n", n, e.tag);
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		Ir->VolUP =>
			ctltab[n].value++;
			if (ctltab[n].value > 100) ctltab[n].value = 100;
			sliderupdate(n);
			ac.puts(sprint("%s %d\n",
				ctltab[n].devnam, ctltab[n].value));
			c.draw();
			status(ac);
		Ir->VolDN =>
			ctltab[n].value--;
			if (ctltab[n].value < 0) ctltab[n].value = 0;
			sliderupdate(n);
			ac.puts(sprint("%s %d\n",
				ctltab[n].devnam, ctltab[n].value));
			c.draw();
			status(ac);
		}
	}
}

slider(env: ref Environ, value: int): ref Element
{
	r: Rect;

	r = ((0,0),(200,20));
	ldepth := display.image.chans;
	icon := display.newimage(r.inset(-2), ldepth, 0, draw->Black);
	icon.draw(r, white, ones, (0,0));
	rr := r;
	rr.max.x = 2*value;
	icon.draw(rr, red, ones, (0,0));
	return Element.icon(env, zr, icon, ones);
}

sliderupdate(n: int)
{
	ell := tl ev.kids;
	el := hd ell;
	for (i := 0; i < n; i++) {
		ell = tl tl ell;
		el = hd ell;
	}
	kids := el.kids;
	kids = tl kids;
	print("%s\n", (hd kids).str);
	(hd kids).str = string ctltab[n].value;
	kids = tl kids;
	img := (hd kids).image;
	r: Rect = ((0,0),(200,20));
	img.draw(r, white, ones, (0,0));
	r.max.x = 2*ctltab[n].value;
	img.draw(r, red, ones, (0,0));
}

topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for(;;) {
		alt{
		m = <-ctoappl =>
			if(m == Mux->MAtop)
				screen.top(windows);
		m = <-ctl =>
			return;
		}
	}
}
