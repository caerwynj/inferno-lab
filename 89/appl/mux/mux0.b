implement Mux;

include "sys.m";
sys: Sys;
open, print, read, tokenize: import sys;

include "draw.m";
draw: Draw;
Display, Font, Image, Rect, Point, Pointer, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "devpointer.m";

include "ir.m";

include "mux.m";

Chans: adt
{
	ir:	int;
	kbd:	int;
	ptr:	int;
};

Remote: adt
{
	m:	Ir;
	in:	chan of int;	# inbound from device
};

Remptr: adt
{
	m:	Devpointer;
	in:	chan of ref Pointer;	# inbound from device
};

ir, irsim: ref Remote;
ptr: ref Remptr;
cur: int;
ncmd: int;
nrun: int;
cmd: array of list of string;
started: array of Chans;
topped: array of int;
ctxt: array of ref Context;
ctomux:	array of chan of int;
topc:	chan of int;
pgrp:	array of int;
pin:	array of int;

mainmenu(display: ref Display, screen: ref Screen): ref Compound
{
	items, line: list of string;

	textfont := Font.open(display, "*default*");
	textstyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.rgb(160, 160, 160),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->White));	# highlightcolor

	env := ref Environ(screen, textstyle);

	fd := open("/services/basic", sys->OREAD);
	if(fd == nil) {
		print("no file /services/basic: %r\n");
		return nil;
	}
	buf := array[1024] of byte;
	n := read(fd, buf, len buf);
	if(n <= 0) {
		print("can't read /services/basic: %r\n");
		return nil;
	}
	fd = nil;

	ncmd = 0;
	cmd = array[20] of list of string;
	topped = array[20] of int;
	(nil, items) = tokenize(string buf[0:n], "\n");
	menu:= Element.elist(env, nil, Prefab->EVertical);
	while(items != nil) {
		(n, line) = tokenize(hd items, ":");
		if(n < 3) {
			print("bad services file\n");
			return nil;
		}
		icon := display.open(hd line);
		if(icon == nil) {
			print("open: %s: %r\n", hd line);
			return nil;
		}
		line = tl line;
		(n, cmd[ncmd++]) = tokenize(hd line, " ");
		if(n < 1) {
			print("bad services file\n");
			return nil;
		}
		line = tl line;
		str := "";
		for(;;) {
			str = str + hd line;
			line = tl line;
			if(line == nil)
				break;
			str += " ";
		}
		deltay := (icon.r.dy()-textfont.height)/2;
		ie:= Element.separator(env, ((0,0), (3,1)), display.color(draw->Black), display.color(draw->Black));
		te := Element.elist(env, ie, Prefab->EHorizontal);
		ie = Element.icon(env, icon.r, icon, display.color(draw->White));
		te.append(ie);
		ie = Element.separator(env, ((0,0), (5, 1)), display.color(draw->Black), display.color(draw->Black));
		te.append(ie);
		zr := Rect((0, deltay), (0, deltay));
		te.append(Element.text(env, str, zr, Prefab->EText));
		te.adjust(Prefab->Adjpack, Prefab->Adjcenter);
		te.clip(te.r.inset(-1));
		
		menu.append(te);

		items = tl items;
	}

	menu.adjust(Prefab->Adjpack, Prefab->Adjup);
#	menu.clip(Rect(menu.r.min, menu.r.min.add((350, 230))));
	menu.clip(((0,0),(256,192)));

	c := Compound.box(env, Point(20,10), Element.text(env, "Selector", ((0,0),(0,0)), Prefab->ETitle), menu);
	c.draw();
	return c;
}

refresh(display:ref Display)
{
	display.startrefresh();
}

loadir(): int
{
#	irc := chan of int;
	irpid := chan of int;
#	mod := load Ir Ir->PATH;
#	if(mod!=nil && mod->init(irc,irpid)>=0){
#		<-irpid;
#		ir = ref Remote (mod, irc);
#	}

	irsimc := chan of int;
	mod := load Ir Ir->SIMPATH;
	if(mod!=nil && mod->init(irsimc,irpid)>=0){
		<-irpid;
		irsim = ref Remote (mod, irsimc);
	}
	return ir!=nil || irsim!=nil;
}

loadptr(): int
{
	ptrc := chan of ref Pointer;
	mod := load Devpointer "/dis/lib/devpointer.dis";
	mod->init();
	pid := chan of (int, string);
	spawn mod->reader("/dev/pointer", ptrc, pid);
	(n, s) := <-pid;
	if(n <  0)
		sys->print("loadptr: %s\n", s);
	ptr = ref Remptr (mod, ptrc);
	return ptr!=nil;
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	if(prefab == nil){
		sys->fprint(sys->fildes(2), "error loading prefab %r\n");
		exit;
	}

	if(!loadir()){
		print("mux: can't initialize ir device: %r\n");
		return;
	}

	if(!loadptr()){
		print("mux: can't initialize pointer device: %r\n");
		return;
	}

	display := Display.allocate(nil);
	if(display == nil){
		print("mux: can't initialize display: %r\n");
		return;
	}
	spawn refresh(display);
	disp := display.image;
	screen := Screen.allocate(disp, display.rgb(161, 195, 209), 1);
	disp.draw(disp.r, screen.fill, display.color(draw->White), disp.r.min);
	menu := mainmenu(display, screen);
	if(menu == nil)
		exit;
	ctxt = array[ncmd] of ref Context;
	ctomux = array[ncmd] of chan of int;
	started = array[ncmd] of Chans;
	pgrp = array[ncmd] of int;
	pin = array[ncmd] of {* => -1};
	topc = chan of int;

	spawn topper();

	sel:= 0;
	nrun = 0;
	cur = -1;
	key: int;
	events := chan of int;
	stop := chan of int;

	for(;;){
		menu.image.top();

		spawn irslave(events, stop);
		(key, sel, nil) = menu.select(menu.contents, sel, events);
		stop <-= 1;

		if(key == Ir->Enter && sel>=0) {
			killcmd(sel);
			continue;
		}
		if(key != Ir->Select)
			continue;
		if(sel>=0)
		if(addcmd(sel, display, screen))
			menu.image.bottom();
		if(cur == -1)
			continue;
		ctl(display, screen);
	}
}

append(l: list of int, i: int): list of int
{
	if(l == nil)
		return i :: nil;
	return hd l :: append(tl l, i);
}

appendptr(l: list of ref Pointer, p: ref Pointer): list of ref Pointer
{
	if(l == nil)
		return p :: nil;
	return hd l :: appendptr(tl l, p);
}

# reads real (if possible) or simulated remote, returns Ir events on irc
irslave(irc, stopc: chan of int)
{
	in: int;
	buf: list of int;
	outc: chan of int;

	remote := ir;
	if(remote == nil)
		remote = irsim;

	hdbuf := 0;
	dummy := chan of int;
	for(;;){
		if(buf == nil){
			outc = dummy;
		}else{
			outc = irc;
			hdbuf = hd buf;
		}
		alt{
		in = <-remote.in =>
			buf = append(buf, in);
		outc <-= remote.m->translate(hdbuf) =>
			buf = tl buf;
		<-stopc =>
			return;
		}
	}
}

# reads keyboard (attached to irsim), returns plain characters
kbdslave(kbdc, stopc: chan of int)
{
	in: int;
	buf: list of int;
	outc: chan of int;

	hdbuf := 0;
	dummy := chan of int;
	for(;;){
		if(len buf == 0){
			outc = dummy;
		}else{
			outc = kbdc;
			hdbuf = hd buf;
		}

		alt{
		in = <-irsim.in =>
			buf = append(buf, in);
		outc <-= hdbuf =>
			buf = tl buf;
		<-stopc =>
			return;
		}
	}
}

# reads pointer , returns ref Pointer events
ptrslave(ptrc: chan of ref Pointer, stopc: chan of int)
{
	in, last: ref Pointer;
	buf: list of ref Pointer;
	outc: chan of ref Pointer;

	hdbuf : ref Pointer = nil;
	dummy := chan of ref Pointer;
	for(;;){
		if(len buf == 0){
			outc = dummy;
		}else{
			outc = ptrc;
			hdbuf = hd buf;
		}
		alt{
		in = <-ptr.in =>
			if(in == nil)
				break;
			if(buf==nil || last==nil || last.buttons!=in.buttons){ # not quite right
				buf = appendptr(buf, in);
				last = in;
			}
		outc <-= hdbuf =>
			buf = tl buf;
		<-stopc =>
			return;
		}
	}
}

addcmd(i: int, display: ref Display, screen: ref Screen): int
{
	if(ctxt[i] != nil){
		topc <-= i;
		cur = i;
		return 1;
	}
	nc := ref Context(screen, display,
		chan of int, chan of int, chan of ref Pointer,
		chan of int, chan of int);
	pgrpchan := chan of int;
	cx := exec(cmd[i], pin[i], nc, pgrpchan);
	if(cx == nil)
		return 0;
	pgrp[i] = <-pgrpchan;
	ctxt[i] = cx;
	ctomux[i] = cx.ctomux;
	cur = i;
	nrun++;
	return 1;
}

killcmd(i: int)
{
	if(ctxt[i] == nil)
		return;
	if (pgrp[i] == 0) {
		print("Killcmd: Can't happen\n");
		exit;
	}
	fname := sys->sprint("#p/%d/ctl", pgrp[i]);
	if ((fdesc := sys->open(fname, sys->OWRITE)) != nil) {
		sys->write(fdesc, array of byte "killgrp\n", 8);
		# Unblock it from blocking system calls:
		alt {
			ctxt[i].cir <-= Ir->Rcl	=> ;
			*			=> ;
		}
	} else
		print("Process %d already dead\n", pgrp[i]);
	topped[i] = 0;
	ctxt[i] = nil;
	ctomux[i] = nil;
	pgrp[i] = 0;
	nrun--;
}

delcmd(i: int)
{
	if(ctxt[i] == nil)
		return;
	topped[i] = 0;
	ctxt[i] = nil;
	ctomux[i] = nil;
	pgrp[i] = 0;
	nrun--;
}

exec(cmd: list of string, pin: int, ctxt: ref Context, pc: chan of int): ref Context
{
	c: Command;
	file: string;

	file = hd cmd + ".dis";
	c = load Command file;
	if(c == nil)
		c = load Command "/dis/mux/"+file;
	if(c == nil) {
		print("%s: not found\n", hd cmd);
		return nil;
	}

	spawn newgroup(c, ctxt, cmd, pin, pc); 
	return ctxt;
}

newgroup(c: Command, ctxt: ref Context, cmd: list of string, pin: int, pc: chan of int)
{
	pc <-= sys->pctl(sys->NEWPGRP, nil);
	if(pin >= 0){
		fd := sys->open("/dev/pin", sys->OWRITE);
		if(fd != nil){
			sys->fprint(fd, "%d", pin);
			fd = nil;
		}
	}
	c->init(ctxt, cmd);
}

topdrain(i: int): int
{
	j: int;

	cx := ctxt[i];
	if(cx == nil){
		topped[i] = 0;
		return 1;
	}

	topped[i] = 1;
	alt{
	j = <-topc =>
		topped[j] = 1;
		return 0;
	cx.ctoappl <-= MAtop =>
		topped[i] = 0;
		return 1;
	* =>
		return 0;
	}
}

# someone is queued to be topped; hang here until otherwise
top1()
{
outer:	for(;;){
		# first, try catching up
		npend := 0;
		for(i:=0; i<ncmd; i++)
			if(topped[i]){
				if(topdrain(i))
					continue outer;
				else
					npend++;
			}
		if(npend == 0)
			return;
		sys->sleep(200);
	}
}

# deal with outgoing top events, without blocking main process
topper()
{
	for(;;){
		if(topdrain(<-topc))
			continue;
		top1();
	}
}

ctl(display: ref Display, screen: ref Screen)
{
	i, m: int;
	cir, ckbd: chan of int;
	cptr: chan of ref Pointer;
	ckdummy := chan of int;
	cidummy := chan of int;
	cpdummy := chan of ref Pointer;
	irc := chan of int;
	kbdc := chan of int;
	ptrc := chan of ref Pointer;
	irstopc := chan of int;
	kbdstopc := chan of int;
	ptrstopc := chan of int;

	ctlX: con 16r18;

	kbdup := 0;
	irup := 0;
	ptrup := 0;
	if(started[cur].kbd){
		spawn kbdslave(kbdc, kbdstopc);
		kbdup = 1;
	}
	else if(started[cur].ir){	# note the 'else'
		spawn irslave(irc, irstopc);
		irup = 1;
	}
	if(started[cur].ptr){
		spawn ptrslave(ptrc, ptrstopc);
		ptrup = 1;
	}

	irval := -1;
	kbdval := -1;
	ptrval: ref Pointer;
out:	for(;;){
		cir = cidummy;
		ckbd = ckdummy;
		cptr = cpdummy;
		if(started[cur].ir && irval>=0)
			cir = ctxt[cur].cir;
		if(started[cur].kbd && kbdval >= 0)
			ckbd = ctxt[cur].ckbd;
		if(started[cur].ptr && ptrval != nil)
			cptr = ctxt[cur].cptr;

		alt{
		irval = <-irc =>
			if(irval == Ir->Rcl)
				break out;

		kbdval = <-kbdc =>
			if(kbdval == ctlX)
				break out;

		ptrval = <-ptrc =>
			;

		cir <-= irval =>
			irval = -1;

		ckbd <-= kbdval =>
			kbdval = -1;

		cptr <-= ptrval =>
			ptrval = nil;

		(i, m) = <-ctomux =>
			case m{
			AMstartir =>
				if(kbdup && ir==nil){	# keyboard is simulating ir
					kbdstopc <-= 1;
					kbdup = 0;
				}
				if(!irup){
					spawn irslave(irc, irstopc);
					irup = 1;
				}
				started[i].ir = 1;
				started[i].kbd = 0;
			AMstartkbd =>
				if(irsim == nil)	# can't do it
					break;
				if(irup && ir==nil){	# keyboard is simulating ir
					irstopc <-= 1;
					irup = 0;
				}
				if(!kbdup){
					spawn kbdslave(kbdc, kbdstopc);
					kbdup = 1;
				}
				started[i].ir = 0;
				started[i].kbd = 1;
			AMstartptr =>
				if(ptr == nil)	# can't do it
					break;
				if(!ptrup){
					spawn ptrslave(ptrc, ptrstopc);
					ptrup = 1;
				}
				started[i].ptr = 1;
			AMexit =>
				delcmd(i);
				if(cur == i)
					break out;
			AMnewpin =>
				delcmd(i);
				newpin(i, display, screen);
				addcmd(i, display, screen);
			* =>
				print("application protocol error: unknown message %d\n", m);
				return;
			}
		}
	}
	cur = -1;
	if(irup)
		irstopc <-= 1;
	if(kbdup)
		kbdstopc <-= 1;
	if(ptrup)
		ptrstopc <-= 1;
}

errmsg(title,msg: string, display: ref Display, screen: ref Screen, events: chan of int)
{

	noentry := display.open("/icons/noentry.bit");
	if(noentry == nil)
		return;

	lightyellow := display.rgb(255, 255, 180-32);
#	lightbluegreen := display.rgb(161, 195, 209);

	font := Font.open(display, "*default*");
	errstyle := ref Style(
			font,				# titlefont
			font,				# textfont
			display.color(draw->White),	# elemcolor
			display.color(draw->Red),	# edgecolor
			display.color(draw->Black),	# titlecolor	
			display.color(draw->Black),	# textcolor
			lightyellow);			# highlightcolor

	errenv := ref Environ(screen, errstyle);
	le := Element.elist(errenv, nil, Prefab->EHorizontal);
	le.append(Element.icon(errenv, noentry.r, noentry, display.color(draw->White)));
	msg = "\n"+msg+"\n\n";
	le.append(Element.text(errenv, msg, ((0, 0), (400, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);
	c := Compound.box(errenv, (100, 100), Element.text(errenv, title, ((0,0),(0,0)), Prefab->ETitle), le);
	c.draw();
	<-events;
}

getpin(msg: string, display: ref Display, screen: ref Screen, events: chan of int): int
{
	i,n: int;
	key: int;
	r: Rect;

	textfont := Font.open(display, "/fonts/lucida/unicode.20.font");

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			display.color(draw->Red),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->White),	# textcolor
			display.color(130));		# highlightcolor

	env := ref Environ(screen, style);

	spin := "? ? ? ?";
	n = 0;
	for(;;){
		r = ((0,0),(400,0));
		et := Element.text(env, "Enter a 4 digit pin to use when accessing "+msg,
			r, Prefab->ETitle);
		e := Element.text(env, spin, r, Prefab->EText);

		c := Compound.box(env, Point(150, 150), et, e);
		c.draw();

out:		for(;;) {
			spin = c.contents.str;
			case key = <-events {
			Ir->Select =>
				n = 0;
				for(i = 0; i < 4; i++){
					if(spin[2*i] == '?'){
						errmsg("bad pin", "pins must be 4 digits", display, screen, events);
						n = i;
						break out;
					}
					n = n*10 + int spin[i];
				}
				return n;
			Ir->Enter =>
				return -1;
			Ir->Zero to Ir->Nine =>
				pin[2*n] = (key - Ir->Zero) + '0';
				n++;
				if(n >= 4)
					n = 0;
				break out;
			}
			c.contents.str = spin;
			c.draw();
		}
	}
}

newpin(i: int, display: ref Display, screen: ref Screen): int
{
	events := chan of int;
	stop := chan of int;
	spawn irslave(events, stop);
	pin[i] = getpin(hd cmd[i], display, screen, events);
	stop <-= 1;
	return pin[i];
}
