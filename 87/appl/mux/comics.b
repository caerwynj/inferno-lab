implement Comics;

include "sys.m";
sys: Sys;
open, print, read, tokenize: import sys;

include "draw.m";
draw: Draw;
Display, Font, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "ir.m";

include "mux.m";
	mux: Mux;
	Context: import mux;

Comics: module
{
	init:	fn(ctxt: ref Mux->Context, argv: list of string);
};

screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
ones: ref Image;

init(ctxt: ref Context, args: list of string)
{
	key: int;
	arg, field: list of string;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;

	ones = display.color(draw->White);
	textfont := Font.open(display, "*default*");

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(16r22),		# elemcolor
			display.color(draw->Black),		# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),		# textcolor
#			display.color(130));			# highlightcolor
			display.color(16r2d));		# highlightcolor

	env = ref Environ(ctxt.screen, style);

	if(args != nil)
		args = tl args;
	comicdir := "";
	if(args != nil)
		comicdir = hd args;
	comicfile := "/services/comics/"+comicdir+"/config";

	comic := open(comicfile, sys->OREAD);
	if(comic == nil) {
		print("open comic: %s: %r", comicfile);
		return;
	}

	buf := array[1024] of byte;
	n := read(comic, buf, len buf);
	if(n <= 0) {
		print("read comic: %r");
		return;
	}
	comic = nil;

	ctxt.ctomux <-= Mux->AMstartir;
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	(nil, arg) = tokenize(string buf[0:n], "\n");

	(nil, line1) := tokenize(hd arg, ":");
	title := display.open(hd line1);
	if(title == nil){
		sys->print("Comics: can't open %s: %r\n", hd line1);
		finish(ctxt, slavectl);
	}
	line1 = tl line1;
	author := "";
	if(line1 != nil)
		author = hd line1;

	arg = tl arg;

	strip := array[len arg] of string;

	i := 0;
	l := "";
	while(arg != nil) {
		(n, field) = tokenize(hd arg, ":");
		strip[i++] = hd field;
		field = tl field;
		l += hd field + "\n";
		arg = tl arg;
	}
	te := Element.icon(env, title.r, title, ones);
	e := Element.text(env, l, ((0,0),(0,0)), Prefab->EText);
	c := Compound.box(env, Point(250, 150), te, e);
	c.draw();

	windows[1] = c.image;

	n = 0;
	for(;;) {
		(key, n, nil) = c.select(c.contents, n, ctxt.cir);
		case key {
		Ir->Select =>
			view(ctxt, title, author, strip[n]);
		Ir->Enter =>
			finish(ctxt, slavectl);
		}
		n++;
		if(n >= i)
			n = 0;
	}
}

finish(ctxt: ref Context, slavectl: chan of int)
{
	slavectl <-= Mux->AMexit;
	ctxt.ctomux <-= Mux->AMexit;
	exit;
}

view(ctxt: ref Context, title: ref Image, author, bitmap: string)
{
	byline := Element.elist(env, nil, Prefab->EHorizontal);
	byline.append(Element.separator(env, ((0,0), (15,0)), ones, display.color(draw->White)));
	byline.append(Element.icon(env, title.r, title, ones));
	byline.append(Element.separator(env, ((0,0), (15,0)), ones, display.color(draw->White)));
	byline.append(Element.text(env, author, ((0,20),(0,20)), Prefab->EText));
	byline.adjust(Prefab->Adjpack, Prefab->Adjleft);

	i := display.open(bitmap);
	ei := Element.icon(env, i.r, i, ones);
	ei.clip(((0,0), (500, 340)));
	c := Compound.box(env, Point(25, 40), byline, ei);
	c.draw();

	windows[0] = c.image;
	for(;;) {
		case <-ctxt.cir {
		Ir->Up =>
			c.scroll(c.contents, (0, -250));
		Ir->Dn =>
			c.scroll(c.contents, (0, 250));
		Ir->Enter or Ir->Select =>
			windows[0] = nil;
			return;
		}
	}
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
