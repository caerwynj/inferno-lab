implement Movie;

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

Movie: module
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

#	bigtv := display.open("/icons/bigtv.bit");
#	if(bigtv == nil) {
#		print("missing background: %r");
		bigtv := display.color(draw->Paleyellow);
#	}

	tvstyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			bigtv,				# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Purpleblue),		# titlecolor, purple-grey	
			display.color(draw->Medgreen),	# textcolor, brown
			display.color(draw->Blue));	# highlightcolor, blue

	menustyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->Greygreen),		# elemcolor
			display.color(draw->Black),	# edgecolor
			yellow,				# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->White));	# highlightcolor

	tvenv := ref Environ(ctxt.screen, tvstyle);

	l := list of { "Drama", "Comedy", "Action", "Horror",
		"Mystery", "Musical", "Western", "Sci-Fi" };

	te = Element.elist(tvenv, nil, Prefab->EVertical);
	for(t := l; t != nil; t = tl t)
		te.append(Element.text(tvenv, hd t, zr, Prefab->EText));

	te.clip(ctxt.screen.image.r);
	te.adjust(Prefab->Adjfill, Prefab->Adjleft);

	mainmenu := Compound.box(tvenv, (0,0), Element.text(tvenv, "Inferno Movie Store", zr, Prefab->ETitle), te);
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
			titles(ctxt.cir, se.str);
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

getword(v: array of byte): int
{
	return (int v[0]<<24)|(int v[1]<<16)|(int v[2]<<8)|int v[3];
}

IndexSZ:	con 50000;
IndexEntry:	con 16;
Dbinfo: adt
{
	info:	string;
	movie:	string;
	trail:	string;
};

titles(cc: chan of int, cat: string)
{
	fd: ref FD;
	l: list of string;
	nmovie, i, key: int;
	selelem: ref Element;
	warp := array[26] of int;

	fd = open("/movies/"+cat, sys->OREAD);
	if(fd == nil) {
		print("open index %s: %r\n", cat);
		return;
	}

	buf := array[IndexSZ] of byte;
	n := read(fd, buf, IndexSZ);
	if(n <= 0) {
		print("read index %s: %r\n", cat);
		return;
	}
	if(n >= IndexSZ) {
		print("IndexSZ too small\n");
		return;
	}

	(nil, l) = sys->tokenize(string buf[0:n], "\n");
	fd = open("/movies/"+cat+".warp", sys->OREAD);
	if(fd == nil) {
		print("open .warp %s: %r\n", cat);
		return;
	}

	if(read(fd, buf, 26*4) != 26*4) {
		print("bad warp %s: %r\n", cat);
		return;
	}
	for(i = 0; i < 26*4; i += 4)
		warp[i/4] = getword(buf[i:i+4]);
	buf = nil;

	fd = open("/movies/"+cat+".idx", sys->OREAD);
	if(fd == nil) {
		print("open .idx %s: %r\n", cat);
		return;
	}

	db := open("/movies/database", sys->OREAD);
	if(fd == nil) {
		print("open database: %r\n");
		return;
	}

	te := Element.elist(menuenv, nil, Prefab->EVertical);
	for(t := l; t != nil; t = tl t)
		te.append(Element.text(menuenv, hd t, Rect((0, 0), (256, 0)),
				Prefab->EText));

	l = nil;

	te.adjust(Prefab->Adjpack, Prefab->Adjup);
	te.clip(Rect((0, 0), (256, 192)));

	nmovie = 0;
	titlemenu := Compound.box(menuenv, (10, 50), Element.text(menuenv, cat, zr, Prefab->ETitle), te);
	windows[Wtitles] = titlemenu.image;
	titlemenu.draw();

out:	for(;;) {
		(key, nmovie, selelem) = titlemenu.select(te, nmovie, cc);
		if(key != Ir->Select) {
			for(i = 0; 25 > i && warp[i] < nmovie; i++)
				;
			case key {
			* => 
				break out;
			Ir->ChanDN =>
				if(i == 25)
					i = -1;
				i++;
			Ir->ChanUP =>
				if(i == 0)
					i = 26;
				i--;
			}
			nmovie = warp[i];
			continue;
		}

		dpos := nmovie * IndexEntry;
		if(seek(fd, big dpos, 0) != big dpos) {
			print("seek .idx %s: %r\n", cat);
			break;
		}
		buf = array[IndexEntry] of byte;
		if(read(fd, buf, IndexEntry) != IndexEntry) {
			print("read .idx %s: %r\n", cat);
			break;
		}

		entry := dbinfo(db, buf);
		if(entry != nil)
			action(cc, entry, selelem);
	}
	windows[Wtitles] = nil;
	titlemenu = nil;
}

trailer(entry: ref Dbinfo, cc: chan of int)
{
	i: int;
	m: Mpeg;
	b: ref Image;

	m = load Mpeg Mpeg->PATH;

	b = display.open("/icons/bigtvchrom.bit");
	if(b == nil) {
		print("no background: %r\n");	
		return;
	}
	te := Element.icon(menuenv, screen.image.r, b, ones);
	video := Compound.box(menuenv, Point(0,0), nil, te);
	windows[Wvideo] = video.image;
	video.draw();

	mr := chan of string;
	s := m->play(display, nil, 0, ((97, 92), (528, 409)), entry.trail, mr);

	if(s != "") {
		windows[Wvideo] = nil;
		video = nil;
		errmsg("The video clip is unavailable",
		"The decoder may be in use by another application. The player reported the error: "+s, cc);
		return;
	}
out:	for(;;) {
		alt {
		<-mr =>
			break out;
		i = <-cc =>
			case i {
			Ir->Select =>
				m->ctl("stop");
			Ir->Up or Ir->Dn =>
				m->ctl("pause");
			}
		}	
	}
	windows[Wvideo] = nil;
}

movie(entry: ref Dbinfo, cc: chan of int)
{
	i: int;
	m: Mpeg;

	m = load Mpeg Mpeg->PATH;
	te := Element.icon(menuenv, screen.image.r, m->keycolor(display), ones);
	video := Compound.box(menuenv, Point(0,0), nil, te);
	windows[Wvideo] = video.image;
	video.draw();
	mr := chan of string;

	s := m->play(display, nil, 0, video.r, entry.movie, mr);

	if(s != "") {
		windows[Wvideo] = nil;
		video = nil;
		errmsg("The video clip is unavailable",
		"The decoder may be in use by another application. The player reported the error: "+s, cc);
		return;
	}
out:	for(;;) {
		alt {
		<-mr =>
			break out;
		i = <-cc =>
			case i {
			Ir->Select =>		m->ctl("stop");
			Ir->Up or Ir->Dn =>	m->ctl("pause");
			}
		}	
	}
	windows[Wvideo] = nil;
}

action(cc: chan of int, entry: ref Dbinfo, selelem: ref Element)
{
	key, i: int;
	ee: ref Element;

	me := Element.text(menuenv, entry.info, Rect((0, 80), (256, 0)), Prefab->EText);
	me = Element.elist(menuenv, me, Prefab->EVertical);

	te := Element.text(menuenv, "Continue", zr, Prefab->EText);
	te = Element.elist(menuenv, te, Prefab->EHorizontal);

	if(entry.trail != nil) {
		ee = Element.text(menuenv, "Trailer", zr, Prefab->EText);
		te.append(ee);
	}
	if(entry.movie != nil) {
		ee = Element.text(menuenv, "Movie", zr, Prefab->EText);
		te.append(ee);
	}
	te.clip(Rect((0, 0), (256, te.r.max.y)));
	te.adjust(Prefab->Adjfill, Prefab->Adjcenter);
	me.append(Element.separator(menuenv, Rect((0, 0),(256,1)), ones, display.color(draw->Black)));
	me.append(te);
	me.adjust(Prefab->Adjpack, Prefab->Adjup);

	c := Compound.box(menuenv, (30, 80), Element.text(menuenv, selelem.str, zr, Prefab->ETitle), me);
	windows[Wdesc] = c.image;
	c.draw();

	for(;;) {
		(key, i, nil) = c.select(te, 0, cc);
		if(key != Ir->Select || i == 0)
			break;
		if(entry.trail == nil && entry.movie == nil)
			break;
		if(i == 1 && entry.trail != nil)
			trailer(entry, cc);
		else
			movie(entry, cc);
	}
	windows[Wdesc] = nil;
}

dbstr(dbfd: ref FD, s, l: int): string
{
	if(s == 0)
		return nil;

	if(seek(dbfd, big s, 0) != big s) {
		print("seek database: %r\n");
		return nil;
	}
	if(l != 0) {
		data := array[l] of byte;
		if(read(dbfd, data, l) != l) {
			print("read database: %r\n");
			return nil;
		}
		return string data;
	}
	data := array[128] of byte;
	if(read(dbfd, data, len data) < 0) {
		print("read database: %r\n");
		return nil;
	}
	str := string data;
	for(i := 0; i < len str && str[i] != '\n'; i++)
		;
	return str[0:i];
}

dbinfo(dbfd: ref FD, buf: array of byte): ref Dbinfo
{
	db := ref Dbinfo("","","");

	db.info  = dbstr(dbfd, getword(buf[0:4]), getword(buf[4:8]));
	db.movie = dbstr(dbfd, getword(buf[8:12]), 0);
	db.trail = dbstr(dbfd, getword(buf[12:16]), 0);

	return db;
}

errmsg(title, msg: string, button: chan of int)
{
	noentry := display.open("/icons/noentry.bit");
	if(noentry == nil)
		return;

	font := Font.open(display, "*default*");
	black := display.color(draw->Black);
	errstyle := ref Style(
			font,				# titlefont
			font,				# textfont
			display.color(draw->White),		# elemcolor
			black,				# edgecolor
			black,				# titlecolor	
			black,				# textcolor
			black);				# highlightcolor

	errenv := ref Environ(screen, errstyle);
	le := Element.elist(errenv, nil, Prefab->EHorizontal);
	le.append(Element.icon(errenv, noentry.r, noentry, ones));
	msg = "\n"+msg+"\n\n";
	le.append(Element.text(errenv, msg, ((0, 0), (400, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);
	c := Compound.box(errenv, (100, 100), Element.text(errenv, title, zr, Prefab->ETitle), le);
	c.draw();
	<-button;
}
