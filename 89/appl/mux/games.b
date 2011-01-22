implement Games;

include "sys.m";

sys: Sys;
FD: import sys;
open, read, seek, print: import sys;

include "draw.m";
draw: Draw;
Display, Rect, Point, Image, Font, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Element, Style, Environ, Compound: import prefab;

include "ir.m";
include "mpeg.m";

include "mux.m";
	mux: Mux;
	Context: import mux;

Games: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

zr: Rect;
ones: ref Image;
screen: ref Screen;
display: ref Display;
menuenv: ref Environ;
windows: array of ref Image;
Wmain: con 3;
Wtitles: con 2;
Wdesc: con 1;
Wvideo: con 0;
Nwindows: con 4;


topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for(;;)
		alt{
		m = <-ctoappl =>
			if(m == Mux->MAtop)
				screen.top(windows);
		m = <-ctl =>
			return;
		}
}

init(ctxt: ref Context, nil: list of string)
{
	n, key: int;
	te, se: ref Element;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;

	display = ctxt.display;
	screen = ctxt.screen;
	windows = array[Nwindows] of ref Image;

	zr = ((0, 0), (0, 0));
	ones = display.color(draw->White);
	yellow := display.color(draw->Yellow);

	textfont := Font.open(display, "*default*");

	bigtv := display.color(draw->Blue);

	tvstyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			bigtv,				# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),		# titlecolor, purple-grey	
			display.color(draw->Black),	# textcolor, brown
			display.color(draw->White));	# highlightcolor, blue

	menustyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->Paleyellow),		# elemcolor
			display.color(draw->Black),	# edgecolor
			yellow,				# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->White));	# highlightcolor

	tvenv := ref Environ(ctxt.screen, tvstyle);

	l := list of { "othello", 
		"connect4", 
		"go", 
		"checkers",
		"board",
		"board0",
		"board1",
		"board2",
		"board3",
		"board4",
		"board5",
		"board6",
		"board7",
		"board8",
		 };

	te = Element.elist(tvenv, nil, Prefab->EVertical);
	for(t := l; t != nil; t = tl t)
		te.append(Element.text(tvenv, hd t, zr, Prefab->EText));

	te.clip(ctxt.screen.image.r);
	te.adjust(Prefab->Adjfill, Prefab->Adjcenter);

	mainmenu := Compound.box(tvenv, (0,0), Element.text(tvenv, "Inferno Games Store", zr, Prefab->ETitle), te);
	windows[Wmain] = mainmenu.image;
	mainmenu.draw();

	# allocate all menus as subwindows of main screen
	menuenv = ref Environ(screen, menustyle);
	ctxt.ctomux <-= Mux->AMstartir;

	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	n = 0;
	for(;;) {
		(key, n, se) = mainmenu.select(mainmenu.contents, n, ctxt.cir);
		case key {
		Ir->Select =>
			addgame(ctxt, se.str);
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

addgame(ctxt:  ref Context, cat: string)
{
	exec(cat, ctxt);
}

 
exec(cmd: string, ctxt: ref Context): int
{
        c: Games;
        file: string;
        cmdline: list of string;
 
        file = cmd + ".dis";
        c = load Games file;
        if(c == nil)
                c = load Games "/dis/mux/"+file;
        if(c == nil) {
                print("%s: not found\n", cmd);
                return 0;
        }
 
        cmdline  = cmd :: cmdline ;
        newgroup(c, ctxt, cmdline);
        return 1;
}

newgroup(c: Games, ctxt: ref Context, cmd: list of string)
{
 #       print("initing %s \n", hd cmd);
        c->init(ctxt, cmd);
}
