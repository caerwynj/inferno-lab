implement Email;

#
# User interface for upas edmail
#

include "sys.m";
sys: Sys;
FD: import sys;

include "draw.m";
draw: Draw;
Context, Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "ir.m";

zr: Rect;
stderr: ref FD;
screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
tenv: ref Environ;
ones: ref Image;

Main:	 con 0;
Message: con 1;

Email: module
{
	init: fn(ctxt: ref Context, argv: list of string);
};

init(ctxt: ref Context, nil: list of string)
{
	key: int;
	se: ref Element;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;

	stderr = sys->fildes(2);

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;
	
	zr = ((0, 0), (0, 0));
	ones = display.ones;
	textfont := Font.open(display, "*default*");

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(130),		# elemcolor; light blue
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.rgb(255, 255, 180-32));	# highlightcolor

	env = ref Environ(ctxt.screen, style);

	tstyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->White),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Black),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.rgb(255, 255, 180-32));	# highlightcolor

	tenv = ref Environ(ctxt.screen, tstyle);

	# Allocate a cmd device
	cmd := sys->open("/cmd/clone", sys->ORDWR);
	if(cmd == nil) {
		sys->fprint(stderr, "can't open /cmd/clone: %r\n");
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}

	# Find out which one
	buf := array[32] of byte;
	n := sys->read(cmd, buf, len buf);
	if(n <= 0) {
		sys->fprint(stderr, "can't exec: %r\n");
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}
	dir := "/cmd/"+string buf[0:n];

	# Start the Command
	n = sys->fprint(cmd, "exec /v/bin/upas/edmail -m");
	if(n <= 0) {
		sys->fprint(stderr, "can't exec: %r\n");
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}

	io := sys->open(dir+"/data", sys->ORDWR);
	if(io == nil) {
		sys->fprint(stderr, "can't open data: %r\n");
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}

	hdrs := readmsgs(io);

	ctxt.ctomux <-= Draw->AMstartir;
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	if(hdrs == nil) {
		slavectl <-= Draw->AMexit;
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}

	envelope := display.open("/icons/envelope.bit");
	if(envelope == nil) {
		sys->fprint(stderr, "can't open envelope.bit: %r\n");
		ctxt.ctomux <-= Draw->AMexit;
		return;
	}

	et := Element.text(env, "E-Mail", zr, Prefab->EText);
	e := Element.elist(env, nil, Prefab->EVertical);
	for(i := 0; i < len hdrs; i++) {
		ee := Element.elist(env, nil, Prefab->EHorizontal);
		ee.append(Element.icon(env, envelope.r, envelope, ones));
		ee.append(Element.text(env, hdrs[i], zr, Prefab->EText));
		ee.adjust(Prefab->Adjpack, Prefab->Adjleft);
		e.append(ee);
	}
	e.adjust(Prefab->Adjpack, Prefab->Adjup);
	e.clip(Rect((0, 0), (600, 400)));
	c := Compound.box(env, Point(10, 10), et, e);
	c.draw();

	windows[Main] = c.image;

	n = 0;
	i = len hdrs;
	for(;;) {
		(key, n, se) = c.select(c.contents, n, ctxt.cir);
		case key {
		Ir->Select =>
			view(ctxt, io, n+1, hdrs[n]);
		Ir->Enter =>
			slavectl <-= Draw->AMexit;
			ctxt.ctomux <-= Draw->AMexit;
			return;
		}
		n++;
		if(n >= i)
			n = 0;
	}
}

view(ctxt: ref Context, io: ref FD, mailno: int, title: string)
{
	key, n: int;
	se: ref Element;
	a: array of string;

	ci := ctxt.cir;

	sys->fprint(io, "%d\n", mailno);

	buf := array[8192] of byte;
	s := "";
	for(;;) {
		r := sys->read(io, buf, len buf);
		if(r <= 0)
			return;

		s += string buf[0:r];
		# sys->print("%d last char %c\n", r, s[len s-1]);
		if(s[len s-1] == '?')
			break;
	}
	s = s[0:len s-2];
	msg := Compound.textbox(tenv, ((10, 54), (610, 400)), title, s);
	msg.draw();
	windows[Message] = msg.image;


	menu := array[] of {
		"Continue",
		"Delete",
		"Reply",
		"Save",
		"Forward" };

	me := Element.elist(env, nil, Prefab->EHorizontal);
	for(i := 0; i < len menu; i++)
		me.append(Element.text(env, menu[i], zr, Prefab->EText));

	me.adjust(Prefab->Adjequal, Prefab->Adjcenter);
	me.clip(((0, 0), (600, 20)));

	et := Element.text(env, "Command", zr, Prefab->EText);
	mc := Compound.box(env, Point(10, 10), et, me);
	mc.draw();

	height := tenv.style.textfont.height;
	nlines := msg.contents.r.dy()/height;
	maxlines := len msg.contents.kids;
	dlines := 0;
	if(nlines != maxlines)
		dlines = 2*nlines/3;
	firstline := 0;

	for(;;) {
		(key, n, se) = mc.select(mc.contents, 0, ci);
		case key {
		Ir->Up =>
			if(dlines>0 && firstline>0) {
				msg.scroll(msg.contents, (0, dlines*height));
				firstline -= dlines;
			}
		Ir->Dn =>
			if(dlines>0 && firstline+nlines<maxlines) {
				msg.scroll(msg.contents, (0, -dlines*height));
				firstline += dlines;
			}
		Ir->Select =>
			p := se.r.min;
			case n {
			0 => # Continue
				windows[Message] = nil;
				return;
			1 => # Delete
				sys->fprint(io, "d\n");
				rdprompt(io);
				windows[Message] = nil;
				return;
			2 => # Reply
				;
			3 => # Save
				a = readfile("folders");
				if(a == nil)
					break;
				key = choose(a, "Choose Folder", p, ci);
				if(key >= 0) {
					sys->fprint(io, "s %s\n", a[key]);
					rdprompt(io);
				}
			4 => # Forward
				a = readfile("forward");
				if(a == nil)
					break;
				key = choose(a, "Choose Address", p, ci);
				if(key >= 0) {
					sys->fprint(io, "m %s\n", a[key]);
					rdprompt(io);
				}
			}
		Ir->Enter =>
			windows[Message] = nil;
			return;
		}
	}
}

choose(a: array of string, title: string, p: Point, ci: chan of int): int
{
	me := Element.elist(env, nil, Prefab->EVertical);
	for(i := 0; i < len a; i++)
		me.append(Element.text(env, a[i], zr, Prefab->EText));

	me.adjust(Prefab->Adjequal, Prefab->Adjcenter);

	et := Element.text(env, title, zr, Prefab->EText);
	mc := Compound.box(env, p, et, me);
	mc.draw();

	(key, n, se) := mc.select(mc.contents, 0, ci);
	case key {
	Ir->Select =>
		return n;
	* =>
		return -1;
	}
}

readfile(name: string): array of string
{
	fd := sys->open("/services/email/"+name, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	(v, l) := sys->tokenize(string buf[0:n], "\n");
	a := array[v] of string;
	for(i := 0; l != nil; l = tl l)
		a[i++] = hd l;

	return a;
}

rdprompt(io: ref FD)
{
	a := array[1] of byte;

	for(;;) {
		if(sys->read(io, a, 1) < 0)
			return;
		if(a[0] == byte '?')
			return;
	}
}

readmsgs(io: ref FD): array of string
{
	s: string;
	msg, n, r: int;
	l: list of string;

	buf := array[8192] of byte;

	#
	# Read up to the ? prompt
	#
	s = "";
	for(;;) {
		r = sys->read(io, buf, len buf);
		if(r <= 0)
			return nil;

		s += string buf[0:r];
		# sys->print("%d last char %c\n", r, s[len s-1]);
		if(s[len s-1] == '?')
			break;
	}

	(n, l) = sys->tokenize(s, "\n");
	while(l != nil) {
		msg = int hd l;
		if(msg != 0)
			break;
		l = tl l;
	}
	# sys->print("%d messages\n", msg);

	hdrs := array[msg] of string;

	pos := 1;
	nhdr := 0;
	while(msg != 0) {
		n = 10;
		if(n > msg)
			n = msg;

		sys->fprint(io, "%d,%dh\n", pos, pos+n-1);
		# sys->print("->%d,%dh\n", pos, pos+n-1);

		s = "";
		for(;;) {
			r = sys->read(io, buf, len buf);
			if(r <= 0)
				return nil;

			s += string buf[0:r];
			# sys->print("%d last char %c\n", r, s[len s-1]);
			if(s[len s-1] == '?')
				break;
		}

		# sys->print("<-(%d)\n%s\n", len s, s);

		pos += n;
		msg -= n;

		(r, l) = sys->tokenize(s, "\n");
		# sys->print("r=%d\n", r);
		r -= 1;
		for(i := 0; i < r; i++) {
			# sys->print("nhdr=%d %s\n", nhdr, hd l);
			hdrs[nhdr++] = hd l;
			l = tl l;
		}
	}
	return hdrs;
}

topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for(;;) {
		alt{
		m = <-ctoappl =>
			if(m == Draw->MAtop)
				screen.top(windows);
		m = <-ctl =>
			return;
		}
	}
}
