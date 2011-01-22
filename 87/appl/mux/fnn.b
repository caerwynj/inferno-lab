implement FNN;

include "sys.m";
FD: import Sys;
sys:	Sys;

include "draw.m";
draw:	Draw;
Display, Rect, Image, Font, Point, Screen: import draw;

include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

screen:	ref Screen;
display: ref Display;
textfont: ref Font;
ones:	ref Image;
backcol:	ref Image;
textcol:	ref Image;
neww:	ref Image;
table:	array of string;
pfd:	ref FD;
rsalt:	int = 0;

FNN: module {
	init:	fn(ctxt: ref Context, argv: list of string);
};

Stable: adt {
	name:	string;
	val:	real;
	slope:	real;
};

L:	con 0;
R:	con 256;
B:	con 166;
H:	con 30;

INTERVAL: con 25;	# refresh interval
MOVE:	con 2;		# bits to move/interval
TOFF:	con 5;		# vertical adjustment of text in window
stable:	array of Stable;

init(ctxt: ref Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
	if (ctxt==nil) {
		sys->print("context nil\n");
		exit;
	}
	display = ctxt.display;
	screen = ctxt.screen;
	ones = display.color(draw->White);
	textfont = Font.open(display, "*default*");
	backrgb := display.rgb2cmap(100,100,128);
	backcol = display.color(backrgb);
	textcol = display.color(draw->White);
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);
	sourcech := chan of int;
	stopch := chan of int;
	newi := display.newimage(((0,0),(2*R,H)), display.image.chans, 0, backrgb);
	neww = screen.newwindow(Rect((L,B), (R,B+H)), 0, backrgb);
	spawn timer(newi, sourcech, stopch);
	ctxt.ctomux <- = Mux->AMstartir;

	for (;;) {
		s: int;
		alt {
		<- sourcech =>
			neww.draw(Rect((L,B), (R,B+H)), newi, ones,
				display.image.r.min);

		s = <-ctxt.cir =>
			case s {
			Ir->Enter or Ir->Select =>
				slavectl <- = Mux->AMexit;
				stopch <- = 0;
				ctxt.ctomux <- = Mux->AMexit;
				return;
			}
		}
	}	
}

timer(newi: ref Image, tch, stopch: chan of int)
{
	s := "Financial News... ";
	i:=0;
	etext := R;
	for (;;) {

		sys->sleep(INTERVAL);
		alt {

		tch <- = 0 =>
			newi.draw(Rect((0,0),(2*R,H)), newi, ones,
			   newi.r.min.add((MOVE,0)));
			newi.draw(Rect((2*R-MOVE,0),(2*R,H)), backcol,
			    ones, newi.r.min);
			etext -= MOVE;
			w := textfont.width(s);
			neww.top();
			if (etext+w < 2*R) {
				newi.text((etext,TOFF), textcol, (0,0),
				      textfont, s);
				etext += w;
				s = nextone();
			}

		<- stopch =>
			return;
		}
	}
}

nextone(): string
{
	if (pfd==nil) {
		stable = array[] of {
			Stable("ORCL", 45.5, 1.03),
			Stable("LU", 27., 1.03),
			Stable("T", 65., .98),
			Stable("NSCP", 98., .98),
			Stable("MSFT", 104., .98),
			Stable("TCOMA", 17., 1.03),
			Stable("TWX", 41., 1.03),
			Stable("SUNW", 45.5, .98),
			Stable("NT", 35., .98),
		};
		pfd = sys->open("/services/price", sys->OREAD);
		if (pfd == nil) {
			sys->print("open file: /services/price: %r\n");
			return "Stock prices unavailable...";
		}
		buf := array[5000] of byte;
		n := sys->read(pfd, buf, len buf);
		s := string(buf[0:n]);
		(nil, stox) := sys->tokenize(s, "\n");
		table = array[len stox] of string;
		for (n=0; stox!=nil; n++) {
			table[n] = hd stox;
			stox = tl stox;
		}
	}
	if (rand(5)==0) {
		w := rand(len stable);
		# bound within random-looking numbers
		if (stable[w].val>13.8 && stable[w].val<785.2)
			stable[w].val = stable[w].slope * stable[w].val;
		return sys->sprint("%s %d%c   ", stable[w].name,
		  int(stable[w].val+0.5), " ¼½¾"[rand(4)]);
	}
	return table[rand(len table)] + "   ";
}

topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for (;;) {
		alt {
		m = <- ctoappl =>
			if (m == Mux->MAtop)
				neww.top();

		m = <- ctl =>
			return;
		}
	}
}

rand(n: int): int
{
	rsalt = rsalt * 1103515245 + 12345;
	if (n==0)
		return 0;
	return ((rsalt&16r7FFFFFFF)>>10) % n;
}
