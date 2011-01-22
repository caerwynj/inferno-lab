implement TvListing;

include "sys.m";
sys: Sys;
FD: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

Progs: adt
{
	r:	Rect;		# draw to
	off:	int;		# file offset of database record
	sel:	int;		# is selected
	text:	string;		# program name
};

Chan: adt
{
	text:	string;		# channel name
	np:	int;		# number of programs
	p:	array of Progs;	# programs in this segment
};

TvListing: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

MAXqrt:		con 16;		# Max quarter hours per screen
MAXrecord:	con 512;		# Max bytes in a tms record
Nfields:	con 26;		# Number of field separators (|) in record
Ybox:		con 35;		# Size of Quarter box
Xbox:		con 40;
Xtitle:		con 60;		# Channel name
Shours:		con 1;
Xsep:		con 2;
Page:		con 4;
Brief:		con 0;
Verbose:	con 1;
START:		con 3;
DURAT:		con 4;
TITLE:		con 5;
SUBTITLE:	con 6;
SYNOPSIS:	con 7;
Guideperiod:	con 7*23;	# One week worth of programs (in hours).

zr: Rect;
zp: Point;
tvenv: ref Environ;
tienv: ref Environ;
selenv: ref Environ;
ones: ref Image;
yellow: ref Image;
lblue: ref Image;
stderr: ref FD;
screen: ref Screen;
display: ref Display;
tmdata: ref FD;
windows: array of ref Image;

init(ctxt: ref Context, nil: list of string)
{
	i: int;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;

	stderr = sys->fildes(2);
	zp = (0, 0);
	zr = (zp, zp);

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[1] of ref Image;

	ones = display.color(draw->White);
	lblue = display.color(draw->Paleblue);
	yellow = display.color(draw->Yellow);
	textfont := Font.open(display, "*default*");

	tvstyle := ref Style(
			textfont,		# titlefont
			textfont,		# textfont
			display.color(draw->Greygreen),	# elemcolor
			display.color(draw->Black),	# edgecolor
			lblue,					# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->Black));	# highlightcolor

	tistyle := ref *tvstyle;
	tistyle.textfont = Font.open(display, "*default*");
 	selstyle := ref *tvstyle;
	selstyle.elemcolor = display.color(draw->Grey);
	selstyle.textcolor = display.color(draw->Black);
	selstyle.highlightcolor = display.color(draw->Red);

	tvenv = ref Environ(ctxt.screen, tvstyle);
	tienv = ref Environ(ctxt.screen, tistyle);
	selenv = ref Environ(ctxt.screen, selstyle);

	tmdata = sys->open("/services/tvlist/tms.feed", sys->OREAD);
	if(tmdata == nil) {
		sys->fprint(stderr, "no tms.feed: %r\n");
		return;
	}

	ctxt.ctomux <-= Mux->AMstartir;

	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	l := readfile("/services/tvlist/list.all");

	hrs := 11;
	mins := 0;
	qrt := 45;

	s := 0;
	e := s+Page;
	if(e > len l)
		e = len l;

	a := chanelem(l[s:e], qrt);

	cx := 0;
	cy := 0;
	a[cy].p[cx].sel = 1;

	for(;;) {
		page(a, hrs, mins);

		key := <-ctxt.cir;
		a[cy].p[cx].sel = 0;
		case key {
		Ir->FF =>
			if(qrt > Guideperiod*4)
				break;
			hrs += Shours;
			hrs %= 24;
			qrt += Shours*4;
			a = chanelem(l[s:e], qrt);
		Ir->Rew =>
			if(qrt < Shours*4)
				break;
			hrs -= Shours;
			hrs %= 24;
			qrt -= Shours*4;
			a = chanelem(l[s:e], qrt);
		Ir->Up =>
			cy--;
			if(cy >= 0)
				break;
			cy++;
			if(s == 0)
				break;
			s--; e--;
			for(i = len a-1; i > 0; i--)
				a[i] = a[i-1];
			a[0] = getprog(l[s], qrt);
		Ir->Dn =>
			cy++;
			if(cy < len a)
				break;
			cy--;
			if(e >= len l-1)
				break;
			s++; e++;
			for(i = 0; i < len a - 1; i++)
				a[i] = a[i+1];
			a[i] = getprog(l[e], qrt);
		Ir->Select =>
			detail(a[cy].p[cx], ctxt.cir);
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
		a[cy].p[cx].sel = 1;
	}
}

detail(p: Progs, key: chan of int)
{
	s := extract(p.off, Verbose);
	if(s == nil)
		return;

	c := Compound.textbox(selenv, ((20, 20), (256,192)), "", s);
	c.draw();
	<-key;		
}

page(a: array of ref Chan, hrs, min: int): ref Compound
{
	e := Element.elist(tvenv, nil, Prefab->EVertical);
	e.append(timeline(hrs, min));
	e.append(body(a));
	e.adjust(Prefab->Adjpack, Prefab->Adjup);
#	e.clip(((0, 0), (256, e.r.max.y)));
	e.clip(((0, 0), (256, 196)));
	t := "TV Guide 12-19 September 1995";
	xe := Element.text(tvenv, t, zr, Prefab->ETitle);
	cmenu := Compound.box(tvenv, Point(10, 10), xe, e);
	cmenu.draw();
	windows[0] = cmenu.image;
	return cmenu;
}

readfile(file: string): array of string
{
	l: list of string;

	fd := sys->open(file, sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[1024] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	(n, l) = sys->tokenize(string buf[0:n], "\n");
	a := array[n] of string;
	for(n = 0; l != nil; l = tl l)
		a[n++] = hd l;
	return a;
}

expand(e: ref Element): ref Element
{
	r := e.r;
	dy := r.dy();
	if(dy >= Ybox)
		return e;
	r.max.y = r.min.y + Ybox;
	e.clip(r);
	e.scroll((0, (dy-Ybox)/2));
	return e;
}

timeline(hours, mins: int): ref Element
{
	xr: Rect;

	e := Element.elist(tvenv, nil, Prefab->EHorizontal);

	sr := (zp, (Xsep, Ybox));
	xr  = (zp, (Xtitle, Ybox));
	xe := Element.text(tvenv, "Time", xr, Prefab->EText);
	e.append(expand(xe));

	xr.max.x = Xbox;
	for(i := 0; i < MAXqrt; i++) {
		xe = Element.separator(tienv, sr, lblue, ones);
		e.append(xe);
		time := sys->sprint("%.2d:%.2d", hours, mins);
		xe = Element.text(tienv, time, xr, Prefab->EText);
		e.append(expand(xe));
		mins += 15;
		if(mins == 60) {
			mins = 0;
			if(hours++ == 24)
				hours = 0;
		}
	}
	e.adjust(Prefab->Adjpack, Prefab->Adjleft);
	return e;
}

chanelem(clist: array of string, quart: int): array of ref Chan
{
	a := array[len clist] of ref Chan;
	for(i := 0; i < len a; i++)
		a[i] = getprog(clist[i], quart);

	return a;
}

body(a: array of ref Chan): ref Element
{
	xe :ref Element;

	sr := (zp, (0, 3));
	e := Element.elist(tvenv, nil, Prefab->EVertical);
	for(i := 0; i < len a; i++) {
		xe = Element.separator(tvenv, sr, lblue, ones);
		e.append(xe);
		e.append(drawelem(a[i]));
	}
	xe = Element.separator(tvenv, sr, lblue, ones);
	e.append(xe);
	e.adjust(Prefab->Adjpack, Prefab->Adjup);
	return e;
}

drawelem(c: ref Chan): ref Element
{
	sr := (zp, (Xsep, Ybox));

	e := Element.elist(tvenv, nil, Prefab->EHorizontal);
	te := Element.text(tvenv, c.text, (zp,(Xtitle, Ybox)), Prefab->EText);
	e.append(te);
	for(i := 0; i < c.np; i++) {
		te = Element.separator(tvenv, sr, lblue, ones);
		e.append(te);
		p := c.p[i];
		if(p.sel)
			te = Element.text(selenv, p.text, p.r, Prefab->EText);
		else
			te = Element.text(tvenv, p.text, p.r, Prefab->EText);
		te.clip(p.r);
		e.append(te);
	}
	e.adjust(Prefab->Adjpack, Prefab->Adjleft);
	return e;
}

getprog(channel: string, quarter: int): ref Chan
{
	xr: Rect;

	c := ref Chan(channel, 0, nil);
	channel = "/services/tvlist/"+channel;
	db := sys->open(channel, sys->OREAD);
	if(db == nil)
		return c;

	quarter *= 4;
	if(sys->seek(db, big quarter, 0) != big quarter)
		return c;

	buf := array[4*MAXqrt] of byte;
	n := sys->read(db, buf, len buf);
	if(n < 4)
		return c;

	np := 0;
	c.p = array[MAXqrt] of Progs;
	last := getword(buf[0:4]);
	prog := extract(last, Brief);
	xr = (zp, (0, Ybox));
	c.p[0] = Progs(xr, last, 0, prog);

	for(i := 0; i < n; i += 4) {
		xr.max.x += Xbox;
		next := getword(buf[i:i+4]);
		if(last != next) {
			prog = extract(last, Brief);
			c.p[np++] = Progs(xr, last, 0, prog);
			xr = (zp, (0, Ybox));
			last = next;
		}
		else
			xr.max.x += Xsep;
	}
	if(np == 0)
		c.p[np++] = Progs(xr, 0, 0, "No Information");
	c.np = np;

	return c;
}

extract(prog, info: int): string
{
	l: list of string;

	if(prog == 0)
		return " ";

	if(sys->seek(tmdata, big prog, 0) != big prog)
		return "Unknown";

	buf := array[MAXrecord] of byte;
	n := sys->read(tmdata, buf, len buf);
	if(n <= 0)
		return "Unknown";

	(n, l) = sys->tokenize(string buf[0:n], "|\n");
	if(n < Nfields)
		return "Unknown";

	fields := array[Nfields] of string;
	for(n = 0; l != nil && n < Nfields; l = tl l)
		fields[n++] = hd l;

	case info {
	Brief =>
		return fields[TITLE];
	Verbose =>
		return fields[TITLE]+"\n"+
		       "Start: "+fields[START]+
		       " Length: "+fields[DURAT]+"\n"+
		       fields[SUBTITLE]+"\n\n"+
		       fields[SYNOPSIS];
	}
	return "";
}

getword(v: array of byte): int
{
	return (int v[0]<<24)|(int v[1]<<16)|(int v[2]<<8)|int v[3];
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
