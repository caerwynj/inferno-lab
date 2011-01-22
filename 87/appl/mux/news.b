implement News;

MENUFONT:	con "*default*";
DIR:		con "/services/news/";
CONFIG:		con "config";

include "sys.m";
sys:	Sys;
open, read: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "mux.m";
	mux: Mux;
	Context: import mux;

include "paper.m";
Article: import PAPER;

include "news.m";

include "ir.m";
include "mpeg.m";

mpeg: Mpeg;
screen: ref Screen;
display: ref Display;
ones, zeros, black, white, blue, red, yellow, green: ref Image;
lightyellow, lightbluegreen, softblue, darkgreen: ref Image;
ctxt:	ref Context;
slavectl:	chan of int;
filmicon:	ref Image;
Newserr	:= "Error in News";

windows: array of ref Image;
Wmain:		con 3;
Whead:		con 2;
Warticle:	con 1;
Wvideo:		con 0;
Nwindows:	con 4;

readline(buf: array of byte, n, nb: int): (int, string)
{
	i: int;

	i = n;
	if(i<nb && int buf[i] == '\n')	# blank line
		return (i+1, "\n\n");
	while(i<nb && int buf[i]!='\n')
		i++;
	if(i < nb)
		return (i+1, string buf[n:i]);
	return (i, string buf[n:i]);
}

readconfigline(buf: array of byte, n, nb: int): (int, ref Paper)
{
	line: string;

	(n, line) = readline(buf, n, nb);
	if(line == "")
		return (0, nil);
	if(line[0:1] == "#")
		return readconfigline(buf, n, nb);
	i: int;
	l: list of string;
	(i, l) = sys->tokenize(line, ":");
	if(i != 2){
		errmsg(Newserr, sys->sprint("bad config line %s\n", line));
		finish();
	}
	title := hd l;
	(i, l) = sys->tokenize(hd tl l, " ");
	if(i != 6){
		errmsg(Newserr, sys->sprint("bad config line %s\n", line));
		finish();
	}
	file := hd l;
	l = tl l;
	menuname := hd l;
	l = tl l;
	fullname := hd l;
	l = tl l;
	headfont := hd l;
	l = tl l;
	textfont := hd l;
	l = tl l;
	modname := "/dis/mux/"+hd l;
	return (n, ref Paper(title, nil, file, menuname, nil, fullname, nil,
		headfont, nil, textfont, nil, modname));
}

readconfig(): list of ref Paper
{
	pl, rl: list of ref Paper;
	p: ref Paper;
	n, nb: int;
	s: string;

	fd := open(DIR+CONFIG, sys->OREAD);
	if(fd == nil){
		errmsg(Newserr, sys->sprint("can't open paper config file: %r"));
		finish();
	}
	buf := array[5000] of byte;
	nb = read(fd, buf, len buf);
	if(nb <= 0){
		errmsg(Newserr, sys->sprint("can't read paper config file: %r\n"));
		finish();
	}
	(n, s) = readline(buf, 0, nb);
	for(;;){
		(n, p) = readconfigline(buf, n, nb);
		if(p == nil)
			break;
		pl = p :: pl;
	}
	# list is in reverse order; reverse again
	while(pl != nil){
		rl = hd pl :: rl;
		pl = tl pl;
	}
	return rl;
}

mainmenu(papers: list of ref Paper): ref Compound
{
	menufont := Font.open(display, MENUFONT);
	if(menufont == nil){
		errmsg(Newserr, sys->sprint("can't open %s: %r\n", MENUFONT));
		finish();
	}
	menustyle := ref Style(
			menufont,	# titlefont
			menufont,	# textfont
			softblue,		# elemcolor
			darkgreen,	# edgecolor
			yellow,		# titlecolor	
			black,		# textcolor
			lightyellow);	# highlightcolor
	menuenv := ref Environ(screen, menustyle);

	he: ref Element;
	e:= Element.elist(menuenv, nil, Prefab->EVertical);
	e.append(Element.separator(menuenv, ((0, 0), (256, 3)), zeros, zeros));
	p: ref Paper;
	for(l:=papers; l!=nil; l=tl l){
		p = hd l;
		p.menuicon = display.open(p.menuname);
		if(p.menuicon == nil){
			errmsg(Newserr, sys->sprint("can't read %s\n", p.menuname));
			continue;
		}
		icon:= p.menuicon;
		deltay := (icon.r.dy()-menustyle.textfont.height)/2;
		he = Element.elist(menuenv, Element.separator(menuenv, ((0, 0), (3, icon.r.dy())), zeros, zeros), Prefab->EHorizontal);
		he.append(Element.icon(menuenv, icon.r, icon, ones));
		he.append(Element.separator(menuenv, ((0,0), (5, 1)), zeros, zeros));
		he.append(Element.text(menuenv, p.title, ((0, deltay), (0, deltay)), Prefab->EText));
		he.adjust(Prefab->Adjpack, Prefab->Adjleft);
		e.append(he);
		e.append(Element.separator(menuenv, ((0, 0), (640, 3)), zeros, zeros));
	}
	e.adjust(Prefab->Adjpack, Prefab->Adjup);
	e.clip(((0,0),(256,192)));
	c := Compound.box(menuenv, Point(120,110), Element.text(menuenv, "Newspapers", ((0,0),(0,0)), Prefab->ETitle), e);
	c.draw();
	return c;
}

selectpaper(c: ref Compound, papers: list of ref Paper, hi:int): (ref Paper, int)
{
	key := 0;
	ee: ref Element;
out:	for(;;){
		(key, hi, ee) = c.select(c.contents, hi, ctxt.cir);
		case key{
		Ir->Enter =>
			return (nil, 0);
		Ir->Select =>
			break out;
		* =>
			continue;
		}
	}
	i := hi;
	for(l:=papers; i>0; l=tl l)
		i--;	
	return (hd l, hi);
}

topslave()
{
	m: int;

	for(;;)
		alt{
		m = <-ctxt.ctoappl =>
			if(m == Mux->MAtop)
				screen.top(windows);
		m = <-slavectl =>
			return;
		}
}

init(actxt: ref Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mpeg = load Mpeg Mpeg->PATH;
	mux = load Mux Mux->PATH;

	ctxt = actxt;
	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[Nwindows] of ref Image;

	ones = display.color(draw->White);
	zeros = display.color(draw->Black);
	black = display.color(draw->Black);
	white = display.color(draw->White);
	blue = display.color(draw->Blue);
	red = display.color(draw->Red);
	yellow = display.color(draw->Yellow);
	green = display.color(draw->Green);
	lightyellow = display.color(draw->Paleyellow);
	lightbluegreen = display.color(draw->Palebluegreen);
	softblue = display.color(draw->Palegreyblue);
	darkgreen = display.color(draw->Darkgreen);

	ctxt.ctomux <-= Mux->AMstartir;
	slavectl = chan of int;
	spawn topslave();
	papers:= readconfig();
	main := mainmenu(papers);
	windows[Wmain] = main.image;
	filmicon = display.open("/icons/film.bit");
	hi := 0;
	p: ref Paper;
	if(filmicon == nil){
		errmsg(Newserr, "can't read /icons/film.bit\n");
		finish();
	}

	for(;;){
		windows[Whead] = nil;
		(p, hi) = selectpaper(main, papers, hi);
		if(p == nil)
			break;
		showpaper(p);
		p = nil;
	}
	finish();
}

showpaper(p: ref Paper)
{
	pm := load PAPER p.modname;
	if (pm==nil) {
		errmsg(Newserr, sys->sprint("can't load module %s: %r\n", p.modname));
		return;
	}
	p.fullicon = display.open(p.fullname);
	if(p.fullicon == nil){
		errmsg(Newserr, sys->sprint("can't read %s\n", p.fullname));
		finish();
	}
	p.headfont = Font.open(display, p.headfontname);
	if(p.headfont == nil){
		errmsg(Newserr, sys->sprint("can't open %s: %r\n", p.headfontname));
		finish();
	}
	p.textfont = Font.open(display, p.textfontname);
	if(p.textfont == nil){
		errmsg(Newserr, sys->sprint("can't open %s: %r\n", p.textfontname));
		finish();
	}
	f := p.file;
	if(f[0]!='/')
		f = DIR+f;
	(date, err, a) := pm->scanpaper(f);
	if(err!=nil && err!="") {
		errmsg("Application error from "+p.modname, err);
		return;
	}
	if(len a == 0)
		return;
	p.date = date;
	
	headstyle := ref Style(
			p.headfont,	# titlefont
			p.headfont,	# textfont
			softblue,		# elemcolor
			darkgreen,	# edgecolor
			yellow,		# titlecolor	
			black,		# textcolor
			lightyellow);	# highlightcolor
	textstyle := ref Style(
			p.textfont,	# titlefont
			p.textfont,	# textfont
			white,		# elemcolor
			blue,			# edgecolor
			red,			# titlecolor	
			black,		# textcolor
			red);			# highlightcolor
	
	
	headenv := ref Environ(screen, headstyle);
	textenv := ref Environ(screen, textstyle);
	
	icon: ref Image;
	deltay := (filmicon.r.dy()-headstyle.textfont.height)/2;
	he: ref Element;
	te:= Element.elist(headenv, nil, Prefab->EVertical);
	t := a;
	while(t != nil){
		icon = headstyle.elemcolor;
		if((hd t).videonm != nil)
			icon = filmicon;
		he = Element.elist(headenv, Element.icon(headenv, filmicon.r.inset(-1), icon, filmicon), Prefab->EHorizontal);
		he.append(Element.text(headenv, (hd t).title, ((0, deltay), (0, deltay)), Prefab->EText));
		he.adjust(Prefab->Adjpack, Prefab->Adjleft);
		te.append(he);
		t = tl t;
	}
	te.adjust(Prefab->Adjpack, Prefab->Adjcenter);
#	if(te.r.dy() > 300)
#		te.clip(Rect(te.r.min,(te.r.min.x+256, te.r.min.y+192)));
	te.clip(((0,0),(256,192-p.fullicon.r.dy())));
	ie:= Element.icon(headenv, p.fullicon.r, p.fullicon, p.fullicon);
	ee := Element.elist(headenv, ie, Prefab->EVertical);
	te.tag = "menu";
	ee.append(te);
	ee.adjust(Prefab->Adjpack, Prefab->Adjup);
	ee.clip(((0,0),(256,192)));
	title:= Element.text(headenv, "Headlines for "+p.date, ((0,0),(0,0)), Prefab->ETitle);
	headlines := Compound.box(headenv, Point(0,0), title, ee);
	headlines.draw();
	windows[Whead] = headlines.image;
	showarticles(pm, headlines, te, a, textenv);
	p.textfont = nil;
	p.headfont = nil;
	p.fullicon = nil;
}

finish()
{
	slavectl <-= Mux->AMexit;	# as good a value as any
	ctxt.ctomux <-= Mux->AMexit;
	exit;
}

showarticles(pm: PAPER, headlines: ref Compound, elem: ref Element, a: list of ref Article, textenv: ref Environ)
{

	ii, j: int;

	ii = 0;
	key := 0;
	ee: ref Element;
	mpegc:= chan of string;
	height:= textenv.style.textfont.height;
	article, video: ref Compound;

outer:
	for(;;){
		(key, ii, ee) = headlines.select(elem, ii, ctxt.cir);
		case key{
		Ir->Enter =>	break outer;
		Ir->Select =>	break;
		* =>		continue;
		}
		t := a;
		for(j=0; j<ii; j++)
			t = tl t;
		art := pm->getarticle((hd t).bodynm);
		if (art==nil || art=="")
			continue;
		article = Compound.textbox(textenv, Rect((10, 60), (10+256, 60+192)), (hd t).title,
			art);
		article.draw();
		windows[Warticle] = article.image;
		mpegc = chan of string;
		if(mpeg!=nil && (hd t).videonm!=nil) {
			tve := Element.icon(textenv, Rect((330,100), (630, 325)), mpeg->keycolor(display), ones);
			video = Compound.box(textenv, Point(330,100), nil, tve);
			video.draw();
			windows[Wvideo] = video.image;
			s := mpeg->play(display, video.image, 1, video.r, "/mpeg/nyt"+(hd t).videonm, mpegc);
			if(s != "") {
				windows[Wvideo] = nil;
				video = nil;
				errmsg("The video clip is unavailable",
				       "The decoder may be in use by another application. The player reported the error: "+s);
			}
		}
		nlines := article.contents.r.dy()/height;
		maxlines := len article.contents.kids;
		dlines: int;
		if(nlines == maxlines)
			dlines = 0;
		else
			dlines = 2*nlines/3;
		firstline := 0;
	out:	for(;;){
			i: int;
			alt{
			<-mpegc =>
				windows[Wvideo] = nil;
				video = nil;
			i = <-ctxt.cir =>
				if(article != nil ) case i {
				Ir->Up =>	if(dlines>0 && firstline>0){
							article.scroll(article.contents, (0, dlines*height));
							firstline -= dlines;
						}
				Ir->Dn =>
						if(dlines>0 && firstline+nlines<maxlines){
							article.scroll(article.contents, (0, -dlines*height));
							firstline += dlines;
						}
				Ir->Enter or
				Ir->Select =>
						windows[Warticle] = nil;
						article = nil;
						if(video != nil)
							mpeg->ctl("stop");
						break out;
				Ir->Rew =>	mpeg->ctl("stop");
				Ir->FF =>		mpeg->ctl("pause");
				}
			}
		}
		windows[Warticle] = nil;
		article = nil;
		if(video != nil){
			<- mpegc;
			windows[Wvideo] = nil;
			video = nil;
		}
	}
}

errmsg(title, msg: string)
{
	noentry := display.open("/icons/noentry.bit");
	if(noentry == nil)
		return;

	font := Font.open(display, "*default*");
	errstyle := ref Style(
			font,				# titlefont
			font,				# textfont
			display.color(draw->White),		# elemcolor
			red,				# edgecolor
			black,				# titlecolor	
			black,				# textcolor
			lightyellow);			# highlightcolor

	errenv := ref Environ(screen, errstyle);
	le := Element.elist(errenv, nil, Prefab->EHorizontal);
	le.append(Element.icon(errenv, noentry.r, noentry, ones));
	msg = "\n"+msg+"\n\n";
	le.append(Element.text(errenv, msg, ((0, 0), (400, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);
	c := Compound.box(errenv, (100, 100), Element.text(errenv, title, ((0,0),(0,0)), Prefab->ETitle), le);
	c.draw();
	<-ctxt.cir;
}
