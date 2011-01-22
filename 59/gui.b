implement Gui;

include "common.m";
include "tk.m";
include "wmclient.m";
	wmclient: Wmclient;

sys : Sys;
draw : Draw;
acme : Acme;
dat : Dat;
utils : Utils;

Font, Point, Rect, Image, Context, Screen, Display, Pointer : import draw;
keyboardpid, mousepid : import acme;
ckeyboard, cmouse : import dat;
mousefd: ref Sys->FD;
error : import utils;

win: ref Wmclient->Window;

r2s(r: Rect): string
{
	return sys->sprint("%d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
}

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;
	wmclient = load Wmclient Wmclient->PATH;
	if(wmclient == nil)
		error(sys->sprint("cannot load %s: %r", Wmclient->PATH));
	wmclient->init();

	if(acme->acmectxt == nil)
		acme->acmectxt = wmclient->makedrawcontext();
	display = (acme->acmectxt).display;
	buts := Wmclient->Appl;
	if((acme->acmectxt).wm == nil)
		buts = Wmclient->Plain;
	win = wmclient->window(acme->acmectxt, "Acme", buts);
	wmclient->win.reshape(((0, 0), (win.displayr.size().div(2))));
	cmouse = chan of ref Draw->Pointer;
	ckeyboard = win.ctxt.kbd;
	wmclient->win.onscreen("place");
	wmclient->win.startinput("kbd"::"ptr"::nil);
	mainwin = win.image;
	
	yellow = display.color(Draw->Yellow);
	green = display.color(Draw->Green);
	red = display.color(Draw->Red);
	blue = display.color(Draw->Blue);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
}

spawnprocs()
{
	spawn mouseproc();
	spawn eventproc();
}

zpointer: Draw->Pointer;

eventproc()
{
	wmsize := startwmsize();
	for(;;) alt{
	wmsz := <-wmsize =>
		win.image = win.screen.newwindow(wmsz, Draw->Refnone, Draw->Nofill);
		p := ref zpointer;
		mainwin = win.image;
		p.buttons = Acme->M_RESIZE;
		cmouse <-= p;
	e := <-win.ctl or
	e = <-win.ctxt.ctl =>
		p := ref zpointer;
		if(e == "exit"){
			p.buttons = Acme->M_QUIT;
			cmouse <-= p;
		}else{
			wmclient->win.wmctl(e);
			if(win.image != mainwin){
				mainwin = win.image;
				p.buttons = Acme->M_RESIZE;
				cmouse <-= p;
			}
		}
	}
}

mouseproc()
{
	for(;;){
		p := <-win.ctxt.ptr;
		if(wmclient->win.pointer(*p) == 0){
			p.buttons &= ~Acme->M_DOUBLE;
			cmouse <-= p;
		}
	}
}
		

# consctlfd : ref Sys->FD;

setcursor(p: Point)
{
	wmclient->win.wmctl("ptr " + string p.x + " " + string p.y);
}

killwins()
{
	wmclient->win.wmctl("exit");
}

startwmsize(): chan of Rect
{
	rchan := chan of Rect;
	fd := sys->open("/dev/wmsize", Sys->OREAD);
	if(fd == nil)
		return rchan;
	sync := chan of int;
	spawn wmsizeproc(sync, fd, rchan);
	<-sync;
	return rchan;
}

Wmsize: con 1+4*12;		# 'm' plus 4 12-byte decimal integers

wmsizeproc(sync: chan of int, fd: ref Sys->FD, ptr: chan of Rect)
{
	sync <-= sys->pctl(0, nil);

	b:= array[Wmsize] of byte;
	while(sys->read(fd, b, len b) > 0){
		p := bytes2rect(b);
		if(p != nil)
			ptr <-= *p;
	}
}

bytes2rect(b: array of byte): ref Rect
{
	if(len b < Wmsize || int b[0] != 'm')
		return nil;
	x := int string b[1:13];
	y := int string b[13:25];
	but := int string b[25:37];
	msec := int string b[37:49];
	return ref Rect((0,0), (x, y));
}
