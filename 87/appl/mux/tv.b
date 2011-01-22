implement Tv;

include "sys.m";
sys: Sys;
FD: import sys;
fprint, sprint, sleep, fildes, open: import sys;

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

Tv: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

Spec: adt
{
	c:	int;
	n:	string;
};

stderr: ref FD;
cfd: ref FD;
ones, zeros: ref Image;
yellow: ref Image;
screen: ref Screen;
display: ref Display;
env, tvenv: ref Environ;
nchan: int;
zr: Rect;
chanlist: array of Spec;
infont: ref Font;
tvwin: ref Compound;	# global to hold up Compound for refresh

pvset: array of int;
pvnam: array of string;
sdset: array of int;
sdnam: array of string;

windows: array of ref Image;

init(ctxt: ref Context, nil: list of string)
{
	key: int;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;

	chanlist = array[] of {
		Spec(1, " 1 Sports"),		Spec(2, " 2 WCBS"),
		Spec(3, " 3 TV3/CTN"),		Spec(4, " 4 WNBC"),
		Spec(5, " 5 Fox"),		Spec(6, " 6 Nickelodeon"),
		Spec(7, " 7 WABC"),		Spec(8, " 8 ESPN"),
		Spec(9, " 9 WWOR"),		Spec(10, "10 Previews"),
		Spec(11, "11 WPIX"),		Spec(12, "12 QVC"),
		Spec(13, "13 WNET"),		Spec(14, "14 HBO"),
		Spec(15, "15 TNT"),		Spec(16, "16 WHSE-TV"),
		Spec(17, "17 Commercial"),	Spec(18, "18 Showtime"),
		Spec(19, "19 Family"),		Spec(20, "20 MSG/C-SPAN2"),
		Spec(21, "21 WLIW"),		Spec(22, "22 MTV"),
		Spec(23, "23 WNJN/HSN"),	Spec(24, "24 USA"),
		Spec(25, "25 WNYE"),		Spec(26, "26 History"),
		Spec(27, "27 Headline News"),	Spec(28, "28 Discovery"),
		Spec(29, "29 A&E"),		Spec(30, "30 Lifetime"),
		Spec(31, "31 WNYC"),		Spec(32, "32 Public access"),
		Spec(33, "33 CNN"),		Spec(34, "34 local access"),
		Spec(35, "35 local access"),	Spec(36, "36 local access"),
		Spec(37, "37 C-SPAN"),		Spec(38, "38 CNBC"),
		Spec(39, "39 Hits 3"),		Spec(40, "40 VC"),
		Spec(41, "41 WXTV"),		Spec(42, "42 VH1"),
		Spec(43, "43 AMC"),		Spec(44, "44 E!"),
		Spec(45, "45 TBS"),		Spec(46, "46 BET"),
		Spec(47, "47 WNJU 47"),		Spec(48, "48 Nashville"),
		Spec(49, "49 Comedy Central"),	Spec(50, "50 Sci-Fi"),
		Spec(51, "51 TLC"),		Spec(52, "52 Weather"),
		Spec(53, "53 WMBC"),		Spec(54, "54 EWTN"),
		Spec(55, "55 Court TV"),	Spec(56, "56 Q2"),
		Spec(57, "57 Prevue"),		Spec(58, "58 WLIG"),
		Spec(59, "59 CTN"),		Spec(60, "60 Food"),
		Spec(68, "68 America Talking"),	Spec(69, "69 Asian"),
		Spec(70, "70 WTZA"),		Spec(71, "71 Hits 2"),
		Spec(74, "74 Hits 1"),		Spec(95, "95 Cinemax"),
		Spec(96, "96 Box/Playbox"),	Spec(98, "98 Disney"),
		Spec(99, "99 NSC")
	};

	stderr = fildes(2);

	cfd = open("/dev/tvctl", sys->ORDWR);
	if(cfd == nil) {
		fprint(stderr, "tv not available\n");
		ctxt.ctomux <-= Mux->AMexit;
		return;
	}
	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;

	ones = display.color(draw->White);
	zeros = display.color(draw->Black);
	yellow = display.color(draw->Yellow);
	textfont := Font.open(display, "*default*");
	infont = Font.open(display, "/fonts/lucida/unicode.20.font");
	if(infont == nil)
		infont = textfont;

	zr = ((0, 0), (0, 0));
	nchan = 4;

	style := ref Style(
			textfont,		# titlefont
			textfont,		# textfont
			display.color(16r55),	# elemcolor
			display.color(draw->Black),	# edgecolor
			yellow,			# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->White));	# highlightcolor

	fprint(cfd, "source 2");
	fprint(cfd, "window 0 0 640 480");
	fprint(cfd, "volume 60 60");
	fprint(cfd, "colorkey 30 50 255 5 30 50");

	# picture value settings
	pvset = array[] of { 0, 55, 55, 0, 15, 55, 50 };
	pvnam = array[] of { "brightness", "contrast", "saturation", "caphue",
			     "capbrightness", "capcontrast", "capsaturation" };
	# sound value settings
	sdset = array[] of { 60, 50, 50 };
	sdnam = array[] of { "volume", "bass", "treble" };

	env = ref Environ(ctxt.screen, style);
	tvstyle := ref *style;
	# set element color to chroma key	# r=255 g=0 b=255 known in device driver
	tvstyle.elemcolor = display.rgb(255, 0, 255);
	tvenv = ref Environ(ctxt.screen, tvstyle);

	drawtv(ctxt.screen.image.r, "");

	ctxt.ctomux <-= Mux->AMstartir;

	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	tc := chan of int;
	exittc := chan of int;
	spawn timer(tc, exittc);

	chgchan();

	for(;;) {
		alt {
		<-tc =>
			clrtext();
		key = <-ctxt.cir =>
			case key {
			Ir->One or
			Ir->Two or
			Ir->Three or
			Ir->Four or
			Ir->Five or
			Ir->Six or
			Ir->Seven or
			Ir->Eight or
			Ir->Nine or
			Ir->Zero =>
				channel(ctxt, key);
			Ir->Select =>
				menu(ctxt);
			Ir->ChanUP =>
				nchan++;
				chgchan();
			Ir->ChanDN =>
				if(nchan > 1)
					nchan--;
				chgchan();
			Ir->VolUP =>
				if(sdset[0] < 100)
					sdset[0] += 5;
				fprint(cfd, "volume %d", sdset[0]);
			Ir->VolDN =>
				if(sdset[0] > 0)
					sdset[0] -= 5;
				fprint(cfd, "volume %d", sdset[0]);
			Ir->Enter =>
				exittc <-= 1;
				slavectl <-= Mux->AMexit;
				ctxt.ctomux <-= Mux->AMexit;
				fprint(cfd, "window 0 0 0 0");
				fprint(cfd, "volume 0 0");
				return;
			}
		}
	}
}

clrtext()
{
	i := windows[0];
	p := i.r.min.add((10, 10));
	i.draw((p, (i.r.max.x-1, p.y+60)), tvenv.style.elemcolor, ones, (0, 0));
}

timer(tc, exittc: chan of int)
{
	i := 0;
	for(;;) {
		sleep(3000);
		alt {
		tc <-= i =>
			i++;
		<-exittc =>
			return;
		* =>
			;
		}
	}
}

chgchan()
{
	i := windows[0];
	p := i.r.min.add((10, 10));

	fprint(cfd, "channel %d 0", nchan);
	s := sprint("%.2d", nchan);
	for(x := 0; x < len chanlist; x++)
		if(nchan == chanlist[x].c)
			s = chanlist[x].n;

	clrtext();
	i.text(p, yellow, p, infont, s);
}

channel(ctxt: ref Context, key: int)
{
	i := windows[0];
	p := i.r.min.add((10, 10));
	s := sprint("%c", key+'0');

	clrtext();
	i.text(p, yellow, p, infont, s);
	key = <-ctxt.cir;
	if(key >= Ir->Zero && key <= Ir->Nine) {
		s += sprint("%c", key+'0');	
		nchan = int s;
		chgchan();
	}
}

chanmenu(ctxt: ref Context)
{
	key, n: int;
	se: ref Element;

	ce := Element.elist(env, nil, Prefab->EVertical);
	n = 0;
	for(i := 0; i < len chanlist; i++) {
		ce.append(Element.text(env, chanlist[i].n, zr, Prefab->EText));
		if(chanlist[i].c == nchan)
			n = i;
	}
	ce.adjust(Prefab->Adjpack, Prefab->Adjup);
	ce.clip(Rect((0, 0), (150, 350)));

	cmenu := Compound.box(env, Point(70, 70), Element.text(env, "Channel List", zr, Prefab->ETitle), ce);
	cmenu.draw();
	windows[2] = cmenu.image;
	(key, n, se) = cmenu.select(ce, n, ctxt.cir);
 	windows[2] = nil;
	if(key != Ir->Select)
		return;
	nchan = chanlist[n].c;
	chgchan();
}

drawtv(r: Rect, s: string)
{
	# r.inset is to adjust for border; resulting window has size r
	c := Compound.box(tvenv, r.min, nil, Element.icon(tvenv, r.inset(1), tvenv.style.elemcolor, ones));
	c.draw();
	if(s != nil)
		c.image.text(c.image.r.min.add((10, 10)), yellow, (0,0), infont, s);
	tvwin = c;
	windows[0] = c.image;
}

sizeposn(ctxt: ref Context)
{
	sr := ctxt.screen.image.r;
	r := windows[0].r;
	clrtext();
	windows[0].text(windows[0].r.min.add((10, 10)), yellow, (0,0), infont, "SP");
	for(;;) {
		case <-ctxt.cir {
		Ir->Enter =>
			drawtv(r, "");
			return;
		Ir->ChanUP =>
			r.min.x -= 12;
			r.min.y -= 9;
			r.max.x += 12;
			r.max.y += 9;
			if(r.dx() > sr.dx())
				r = sr;
		Ir->ChanDN =>
			if(r.dx() > 2*12){
				r.min.x += 12;
				r.min.y += 9;
				r.max.x -= 12;
				r.max.y -= 9;
			}
		Ir->Up =>
			r.min.y -= 9;
			r.max.y -= 9;
			if(r.min.y < 0){
				r.max.y -= r.min.y;
				r.min.y = 0;
			}
		Ir->Dn =>
			r.min.y += 9;
			r.max.y += 9;
			if(r.max.y > sr.max.y){
				r.min.y -= (r.max.y-sr.max.y);
				r.max.y = sr.max.y;
			}
		Ir->Rew =>
			r.min.x -= 12;
			r.max.x -= 12;
			if(r.min.x < 0){
				r.max.x -= r.min.x;
				r.min.x = 0;
			}
		Ir->FF =>
			r.min.x += 12;
			r.max.x += 12;
			if(r.max.x > sr.max.x){
				r.min.x -= (r.max.x-sr.max.x);
				r.max.x = sr.max.x;
			}
		Ir->Select =>
			r = ctxt.screen.image.r;
		}
		if(r.dx()==windows[0].r.dx() && r.dy()==windows[0].r.dy())
			windows[0].origin(windows[0].r.min, r.min);
		else {
			drawtv(r, "SP");
			r = windows[0].r;
		}

		fprint(cfd, "window %d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
	}
}

menu(ctxt: ref Context)
{
	key, n: int;

	l := "Channel Select\nSound Settings\nPicture Control\nSize & Position";
	te := Element.text(env, l, zr, Prefab->EText);

	mainmenu := Compound.box(env, Point(70, 70), Element.text(env, "TV control", zr, Prefab->ETitle), te);
	mainmenu.draw();
	windows[1] = mainmenu.image;
	(key, n, nil) = mainmenu.select(te, 0, ctxt.cir);
	windows[1] = nil;
	mainmenu = nil;

	if(key == Ir->Enter)
		return;

	case n {
	0 =>	chanmenu(ctxt);
	1 =>	set(ctxt, "Sound Settings", sdnam, sdset);
	2 =>	set(ctxt, "Picture Control", pvnam, pvset);
	3 =>	sizeposn(ctxt);
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

gauge(i: ref Image, val: int)
{
	r := i.r;
	i.draw(r, env.style.elemcolor, ones, (0, 0));
	r = r.inset(5);
	i.draw(r, display.color(draw->Black), ones, (0, 0));
	r = r.inset(1);
	i.draw(r, env.style.elemcolor, ones, (0, 0));
	r.max.x = r.min.x + r.dx()*val/100;
	i.draw(r, yellow, ones, (0, 0));
}

set(ctxt: ref Context, title: string, l: array of string, set: array of int)
{
	key, n: int;
	se: ref Element;
	iv := array[len l] of ref Image;

	te := Element.elist(env, nil, Prefab->EVertical);
	for(t := 0; t < len l; t++) {
		le := Element.elist(env, nil, Prefab->EHorizontal);
		i := display.newimage(((0,0), (100, 30)), display.image.chans, 0, 0);
		iv[t] = i;
		gauge(i, set[t]);
		le.append(Element.icon(env, i.r, i, ones));
		le.append(Element.text(env, l[t], zr, Prefab->EText));
		le.adjust(Prefab->Adjpack, Prefab->Adjleft);
		te.append(le);
	}
	te.adjust(Prefab->Adjpack, Prefab->Adjup);

	pc := Compound.box(env, Point(70, 70), Element.text(env, title, zr, Prefab->ETitle), te);
	pc.draw();

	for(;;) {
		(key, n, se) = pc.select(te, n, ctxt.cir);
	out:	for(;;) {
			case key {
			Ir->VolUP or Ir->ChanUP =>	if(set[n] < 100) set[n] += 5;
			Ir->VolDN or Ir->ChanDN =>	if(set[n] > 0) set[n] -= 5;
			Ir->Up or Ir->Dn =>		break out;
			* =>				return;
			}
			gauge(iv[n], set[n]);
			pc.draw();
			fprint(cfd, "%s %d", l[n], set[n]);
			pc.highlight(se, 1);
			se.tag = "";
			key = <-ctxt.cir;
		}
	}
}
