implement RecPb;

include "sys.m";
sys: Sys;
FD, open, print, sprint, read, tokenize: import sys;

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

RecPb: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

textfont: ref Font;

bufsize: con 16*1024;

screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
z  := (0,0);
zr := ((0,0),(0,0));
c: ref Compound;

sliderbackground: ref Image;
sliderpattern: ref Image;
pushicon, popicon: ref Image;

fileicon: ref Image;

Namedimg: adt {
	icon:	ref Image;
	name:	string;
	tag:	string;
};

theicons := array [10] of { Namedimg
	(nil, "pause.bit", "pause"),
	(nil, "play.bit", "play"),
	(nil, "rec.bit", "record"),
	(nil, "rew.bit", "rewind"),
	(nil, "stop.bit", "stop"),
	(nil, "ff.bit", "fastforward"),
	(nil, "cd.bit", "cd"),
	(nil, "line.bit", "line"),
	(nil, "mic.bit", "mic"),
	(nil, "speaker.bit", "speaker")
};
Pause, Play, Record, Rewind, Stop, Fastforward,
	Cd, Line, Mic, Speaker, Playing, Recording, Exit: con iota;

curcontrol := Stop;
curselect := Mic;

pausing := 0;	# booleans
recording := 0;
playing := 0;

slicon, sliconicon: ref Image;

ones, zeros, black, white, blue, red, yellow, grey: ref Image;

icondir: string;
datadir: string;

Ctl: adt {
	devnam:		string;
	invalue:	int;
	outvalue:	int;
};


ctltab := array[20] of { Ctl
# Keep these first three items in the same order as in theicons
	("cd",		 50,   0),
	("line",	 50,   0),
	("mic",		100,   0),

	("audio",	 -1,  60),
	("speaker",	 -1, 100),
	("treb",	 -1,  50),
	("bass",	 -1,  50),
	("", 0, 0)
};
Vol_Output: con 3;

stopflag: int;
volctl: int;

curfile := 0;

init(ctxt: ref Context, nil: list of string)
{
	key: int;
	e: ref Element;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;

	icondir = "/icons/rec-pb/";
	datadir = "/services/rec-pb/";


	for (i := 0; i < len ctltab && ctltab[i].devnam != nil; i++) {
		setvolume(i);
	}

	while (sys->open(datadir + string curfile, sys->OREAD) != nil)
		curfile++;

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[1] of ref Image;

	ones = display.color(draw->White);
	zeros = display.color(draw->Black);
	black = display.color(draw->Black);
	white = display.color(draw->White);
	blue = display.color(16rf4);
	red = display.color(draw->Red);
	yellow = display.color(draw->Yellow);
	grey = display.rgb(192, 192, 192);

	for (i = 0; i < len theicons; i++) {
		theicons[i].icon = display.open(icondir+theicons[i].name);
		if (theicons[i].icon == nil) {
			print("RecPb: Can't open %s: %r\n",
				icondir + theicons[i].name);
			return;
		}
	}

	sliderbackground = display.open(icondir + "slider.bit");
	if (sliderbackground == nil) {
		print("RecPb: Can't open %s: %r\n", icondir + "slider.bit");
		exit;
	}
	sliderpattern = display.open(icondir + "sliderpattern.bit");
	if (sliderpattern == nil) {
		print("RecPb: Can't open %s: %r\n",
			icondir + "sliderpattern.bit");
		exit;
	}
	sliderpattern.clipr = ((-10000,-10000), (10000, 10000));
	sliderpattern.repl = 1;
	pushicon = display.open(icondir + "push.bit");
	if (pushicon == nil) {
		print("RecPb: Can't open %s: %r\n", icondir + "push.bit");
		exit;
	}
	popicon = display.open(icondir + "pop.bit");
	if (popicon == nil) {
		print("RecPb: Can't open %s: %r\n", icondir + "pop.bit");
		exit;
	}

	textfont = Font.open(display, "*default*");

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			grey,				# elemcolor
			black,				# edgecolor
			display.color(130),		# titlecolor	
			black,				# textcolor
			red);			# highlightcolor

	env = ref Environ (ctxt.screen, style);

	c = makecompound();

	push(curselect);

	volctl = Vol_Output;
	sliderupdate(slicon, ctltab[Vol_Output].outvalue);
	sliconicon.draw(sliconicon.r, theicons[Speaker].icon, ones, z);
	thumbset(fileicon, 2, curfile);

	c.draw();

	windows[0] = c.image;

	ctxt.ctomux <-= Mux->AMstartir;
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	ch0 := chan of int;
	ch1 := chan of int;
	ch2 := chan of int;

	spawn volfilter(ctxt.cir, ch0);
	spawn rec_pb(ch1, ch2);
	spawn dispmgr(ch2);

	n := 0;
	for(;;) {
		(key, n, e) = c.tagselect(c.contents, n, ch0);
		case key {
		Ir->Select =>
			ch1 <- = n;
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ch1 <- = Exit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

dispmgr(ch: chan of int)
{
	pushed: int = 0;

	for (;;) {
		n := <- ch;
		case(n) {
		Cd or Line or Mic =>
			if (curselect != n) {
				pop(curselect);
				sliconicon.draw(sliconicon.r,
					theicons[n].icon,
					ones, z);
				volctl = n - Cd;
				sliderupdate(slicon,
					ctltab[volctl].invalue);
				curselect = push(n);
			}
		Pause =>
			if (pausing) push(n); else pop(n);
		Play =>
			if (pushed != n) {
				pop(pushed);
			}
			pushed = push(n);
			sliconicon.draw(sliconicon.r,
				theicons[Speaker].icon, ones, z);
			volctl = Vol_Output;
			sliderupdate(slicon,
				ctltab[volctl].outvalue);
			n = Pause;
		Record =>
			if (pushed != n) {
				pop(pushed);
			}
			pushed = push(n);
			sliconicon.draw(sliconicon.r,
				theicons[curselect].icon, ones, z);
			volctl = curselect - Cd;
			sliderupdate(slicon,
				ctltab[volctl].invalue);
			n = Pause;
		Rewind =>
			if (curfile) {
				curfile--;
				thumbset(fileicon, 2, curfile);
			}
		Stop =>
			if (pushed != n) {
				pop(pushed);
			}
			pushed = push(n);
		Fastforward =>
			if (sys->open(datadir + string curfile,
			    sys->OREAD) != nil) {
				curfile++;
				thumbset(fileicon, 2, curfile);
			}
		Exit =>
			return;
		}
		c.draw();
	}
}

rec_pb(inch, outch: chan of int)
{
	cmd: int;
	fd, dev: ref FD;
	buf := array[bufsize] of byte;
	t := 0;

	for (;;) {
		if ((pausing == 0) && (recording || playing)) {
			alt {
			cmd = <- inch =>
				;
			* =>
				if (recording)
					cmd = Recording;
				else
					cmd = Playing;
			}
		} else
			cmd = <- inch;
		case cmd {
		Pause =>
			pausing = 1 - pausing;
			outch <- = Pause;
		Stop =>
			recording = 0;
			playing = 0;
			pausing = 0;
			dev = nil;
			fd = nil;
			print("%d\n", t);
			outch <- = Stop;
		Record =>
			if (recording && pausing) {
				pausing = 0;
				outch <- = Pause;
				continue;
			}
			if (playing || recording) {
				continue;
			}
			fd = sys->create(datadir+string curfile, sys->OWRITE,
				8r666);
			if (fd == nil) {
				print("Sorry\n");
				continue;
			}
			dev = sys->open("/dev/audio", sys->OREAD);
			if (dev == nil) {
				print("Can't open /dev/audio, %r\n");
				continue;
			}
			t = 0;
			recording = 1;
			outch <- = Record;
		Play =>
			if (playing && pausing) {
				pausing = 0;
				outch <- = Pause;
				continue;
			}
			if (playing || recording) {
				continue;
			}
			fd = sys->open(datadir+string curfile, sys->OREAD);
			if (fd == nil) {
				curfile = 0;
				thumbset(fileicon, 2, curfile);
				fd = sys->open(datadir+"0", sys->OREAD);
				if (fd == nil) {
					print("Sorry\n");
					continue;
				}
			}
			dev = sys->open("/dev/audio", sys->OWRITE);
			if (dev == nil) {
				print("Can't open /dev/audio, %r\n");
				continue;
			}
			playing = 1;
			t = 0;
			outch <- = Play;
		Recording =>
			n := sys->read(dev, buf, bufsize);
			if (n <= 0) {
				print("rd /dev/audio %d\n", n);
				recording = 0;
				dev = nil;
				fd = nil;
				outch <- = Stop;
				continue;
			}
			sys->write(fd, buf, n);
			t += n;
		Playing =>
			n := sys->read(fd, buf, bufsize);
			if (n <= 0) {
				playing = 0;
				dev = nil;
				fd = nil;
				outch <- = Stop;
				continue;
			}
			sys->write(dev, buf, n);
			t += n;
		Exit =>
			outch <- = cmd;
			return;
		* =>
			outch <- = cmd;
		}
	}
}

volfilter(inchan, outchan: chan of int)
{
	for (;;) {
		chr := <-inchan;
		case chr {
		Ir->VolUP =>
			if (volctl != Vol_Output) {
				ctltab[volctl].invalue += 2;
				if (ctltab[volctl].invalue > 100)
					ctltab[volctl].invalue = 100;
			} else {
				ctltab[Vol_Output].outvalue += 2;
				if (ctltab[Vol_Output].outvalue > 100)
					ctltab[Vol_Output].outvalue = 100;
			}
		Ir->VolDN =>
			if (volctl) {
				ctltab[volctl].invalue -= 2;
				if (ctltab[volctl].invalue < 0)
					ctltab[volctl].invalue = 0;
			} else {
				ctltab[Vol_Output].outvalue -= 2;
				if (ctltab[Vol_Output].outvalue < 0)
					ctltab[Vol_Output].outvalue = 0;
			}
		Ir->Enter =>
			outchan <-= Ir->Enter;
			return;
		* =>
			outchan <-= chr;
			continue;
		}
		if (volctl != Vol_Output)
			sliderupdate(slicon, ctltab[volctl].invalue);
		else
			sliderupdate(slicon, ctltab[volctl].outvalue);
		setvolume(volctl);
		c.draw();
	}
}

setvolume(n: int)
{
	b: array of byte;

	devvolume := sys->open("/dev/volume", sys->OWRITE);
	s := ctltab[n].devnam;
	iv := ctltab[n].invalue;
	ov := ctltab[n].outvalue;
	if (iv == -1 && ov == -1) {
		b = array of byte sprint("%s\n", s);
	} else	if (iv == -1) {
		b = array of byte sprint("%s out %d\n", s, ov);
	} else	if (ov == -1) {
		b = array of byte sprint("%s in %d\n", s, iv);
	} else	if (iv == ov) {
		b = array of byte sprint("%s %d\n", s, iv);
	} else {
		b = array of byte sprint("%s in %d out %d\n", s, iv, ov);
	}
	sys->write(devvolume, b, len b);
}

push(n: int): int
{
	theicons[n].icon.draw(theicons[n].icon.r, pushicon, pushicon, z);
	return n;
}

pop(n: int)
{
	theicons[n].icon.draw(theicons[n].icon.r, popicon, popicon, z);
}

makecompound(): ref Compound
{
	et := Element.text(env, "DAF: Digital Audio File", zr, Prefab->ETitle);
	sep := Element.separator(env, (z,(8,8)), zeros, zeros);
	sep1 := Element.separator(env, (z,(24,24)), zeros, zeros);
	e0 := Element.elist(env, nil, Prefab->EVertical);	e0.append(sep);
	e1 := Element.elist(env, nil, Prefab->EHorizontal);	e1.append(sep);
	e2 := Element.elist(env, nil, Prefab->EVertical);
	e3 := Element.elist(env, nil, Prefab->EHorizontal);
	for (i := Pause; i < Rewind; i++) {
		el := Element.icon(env, zr, theicons[i].icon, ones);
		el.tag = theicons[i].tag;
		e3.append(el);					e3.append(sep);
	}
	e3.adjust(Prefab->Adjpack, Prefab->Adjleft);
	e2.append(e3);
	e3 = Element.elist(env, nil, Prefab->EHorizontal);
	for (i = Rewind; i <= Fastforward; i++) {
		el := Element.icon(env, zr, theicons[i].icon, ones);
		el.tag = theicons[i].tag;
		e3.append(el);					e3.append(sep);
	}
	e3.adjust(Prefab->Adjpack, Prefab->Adjleft);		e2.append(sep);
	e2.append(e3);
	e2.adjust(Prefab->Adjpack, Prefab->Adjup);
	e1.append(e2);						e1.append(sep1);

	e2 = Element.elist(env, nil, Prefab->EHorizontal);
	for (i = Cd; i <= Mic; i++) {
		el := Element.icon(env, zr, theicons[i].icon, ones);
		el.tag = theicons[i].tag;
		e2.append(el);					e2.append(sep);
	}
	e2.adjust(Prefab->Adjpack, Prefab->Adjleft);
	e1.append(e2);
	e1.adjust(Prefab->Adjpack, Prefab->Adjleft);
	e0.append(e1);						e0.append(sep1);
	e1 = Element.elist(env, nil, Prefab->EHorizontal);	e1.append(sep);
	fileicon = thumbwheel(2);
	e1.append(Element.icon(env, zr, fileicon, ones));	e1.append(sep1);
	slicon = slider(0);
	e1.append(Element.icon(env, zr, slicon, ones));		e1.append(sep);
	sliconicon = display.open(icondir + "speaker.bit");
	e1.append(Element.icon(env, zr, sliconicon, ones));
	e1.adjust(Prefab->Adjpack, Prefab->Adjleft);
	e0.append(e1);						e0.append(sep);
	e0.adjust(Prefab->Adjpack, Prefab->Adjup);

	return Compound.box(env, Point(350, 200), et, e0);
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

thumbset(icon: ref Image, digits, value: int)
{
	dw := textfont.width("0");
	dh := textfont.height;
	for (i := digits-1; i >= 0; i--) {
		dig := value % 10;
		value = value / 10;
		r := ((i*(dw+4),0),((i+1)*(dw+4)-4, dh));
		icon.draw(r, grey, ones, z);
		icon.text((i*(dw+4),0), red, z, textfont, string dig);
	}
}

thumbwheel(digits: int): ref Image
{
	dw := textfont.width("0");
	dh := textfont.height;
	r: Rect = (z, (digits*(dw+4)-4, dh));
	icon := display.newimage(r.inset(-4), sliderbackground.chans, 0, 0);
	edge_v := display.open(icondir + "edge-v.bit");
	edge_v.repl = 1;
	edge_v.clipr = r.inset(-4);
	for (i := 0; i <= digits; i++) {
		rr := ((i*(dw+4)-4,r.min.y), (i*(dw+4), r.max.y));
		icon.draw(rr, edge_v, ones, z);
	}
	edge_h := display.open(icondir + "edge-h.bit");
	edge_h.repl = 1;
	edge_h.clipr = r.inset(-4);
	icon.draw(((r.min.x,r.min.y-4), (r.max.x,r.min.y  )), edge_h, ones, z);
	icon.draw(((r.min.x,r.max.y  ), (r.max.x,r.max.y+4)), edge_h, ones, z);
	ul := display.open(icondir + "corner-ul.bit");
	ur := display.open(icondir + "corner-ur.bit");
	ll := display.open(icondir + "corner-ll.bit");
	lr := display.open(icondir + "corner-lr.bit");
	icon.draw(((r.min.x-4,r.min.y-4),(r.min.x  ,r.min.y  )), ul, ones, z);
	icon.draw(((r.max.x  ,r.min.y-4),(r.max.x+4,r.min.y  )), ur, ones, z);
	icon.draw(((r.min.x-4,r.max.y  ),(r.min.x  ,r.max.y+4)), ll, ones, z);
	icon.draw(((r.max.x  ,r.max.y  ),(r.max.x+4,r.max.y+4)), lr, ones, z);
	return icon;
}

slider(value: int): ref Image
{
	r: Rect = (z, (100, 20));
	icon := display.newimage(r.inset(-4), sliderbackground.chans, 0, 0);
	icon.draw(r.inset(-4), sliderbackground, ones, z);
	r.max.x = value;
	icon.draw(r, sliderpattern, ones, z);
	return icon;
}

sliderupdate(icon: ref Image, value: int)
{
	r: Rect = (z, (100, 20));
	icon.draw(r.inset(-4), sliderbackground, ones, z);
	r.max.x = value;
	icon.draw(r, sliderpattern, ones, z);
}
