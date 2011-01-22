implement Scope;

# code derived from Caerwyn's ipn lab 12
# revisited by Salva Peiró

# todo: resizal with freq plot, windowing of fft,
# and provide divs/units axis of plots ...
include "draw.m";
	draw: Draw;
	Rect, Image, Display, Screen, Point, Font: import draw;
include "math.m";
	math: Math;
include "fft.m";
	fft: FFT;
include "sys.m";
	sys: Sys;
	sprint, print: import sys;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;
include "arg.m";
	arg: Arg;

Scope: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

fdin: ref sys->FD;		# data input
display: ref Display;
tpic: ref Image; 		# time plot
fpic: ref Image; 		# freq plot

zp:= Point(0,0);
winsz:= Point(240,260);	# hold the current scope size
nsamples := 0;			# number of samples
rate := 22050;			# data adquisition rate
fps := 25;				# frames per second around 15±10
gdiv:= 8;				# number of grid divisions
chans := 1;				# number of channels recorded
outflag := 0;			# write data to stdout
freqflag := 0;			# show frequency spectrum, by default time domain is shown 
stoptimer := 0;			# stop generation of timer ticks

usage()
{
	ferr:=sys->fildes(2);
	sys->fprint(ferr, "usage: scope [-hof] [-c 1|2] [-r rate] [-s fps] infile\n\n");
	exit;
}

scofont: con "/fonts/lucidasans/euro.7.font";
scopecfg := array[] of {
	"frame .cf",
	"panel .t",
	"panel .f",
	
	"label .cf.lc -text {chans} -font "+scofont,
	"entry .cf.c -width 20 -font "+scofont,
	"bind  .cf.c <Key-\n> {send cmd new} ",
	"label .cf.lr -text {rate} -font "+scofont,
	"entry .cf.r -width 45 -font "+scofont,
	"bind  .cf.r <Key-\n> {send cmd new}",
	"label .cf.lf -text {fps} -font "+scofont,
	"entry .cf.f -width 20 -font "+scofont,
	"bind  .cf.f <Key-\n> {send cmd new} ",
	"label .cf.lg -text {gfiv} -font "+scofont,
	"entry .cf.g -width 30 -font "+scofont,
	"bind  .cf.g <Key-\n> {send cmd new} ",
	"checkbutton .cf.freq -text {Freq} -command {send cmd freq} -font "+scofont,
	
	"pack .cf.lc .cf.c .cf.lr .cf.r .cf.lf .cf.f .cf.lg .cf.g .cf.freq -side left",
	"pack .cf -side top -fill x",
	"pack .f .t -side bottom -fill both -expand true",
	"bind .t <ButtonPress-1> +{send cmd but1 %X, %Y}",
	"update"
};

init(ctxt: ref Draw->Context, args: list of string)
{
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	arg = load Arg Arg->PATH;
	fft = load FFT FFT->PATH;

	arg->init(args);
	while((o := arg->opt()) != 0)
		case o {
		'c' => chans = int arg->arg();
			if (chans<1 || chans>2)
				usage();
		'r' =>
			rate = int arg->arg();
			if (rate<8000 || rate>44100)
				usage();
		'f' => freqflag = 1;
		's' => fps = int arg->arg();
			if (fps<5 || fps>30)
				usage();
		'o' => outflag = 1;
		* =>
			usage();
		}
	args = arg->argv();
	if (len args > 0){
		if (hd args == "-")
			fdin = sys->fildes(0);
		else
			fdin = sys->open(hd args, sys->OREAD);
		if(fdin == nil){
			sys->print("open: %r\n");
			raise "fail:bad open";
		}
	}else
		fdin = sys->fildes(0);
	
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	tkclient->init();
	(top, ctl) := tkclient->toplevel(ctxt, nil, "Scope", Tkclient->Appl);

	ccmd := chan of string;
	tick := chan of int;
	tk->namechan(top, ccmd, "cmd");
	for (i:=0; i<len scopecfg; i++)
		tk->cmd(top, scopecfg[i]);
	tk->cmd(top, ".cf.c delete 0 end");
	tk->cmd(top, ".cf.r delete 0 end");
	tk->cmd(top, ".cf.f delete 0 end");
	tk->cmd(top, ".cf.g delete 0 end");
	tk->cmd(top, ".cf.c insert 0 " + string(chans));
	tk->cmd(top, ".cf.r insert 0 " + string(rate));
	tk->cmd(top, ".cf.f insert 0 " + string(fps));	
	tk->cmd(top, ".cf.g insert 0 " + string(gdiv));	
	if (freqflag)
		tk->cmd(top, ".cf.freq select");
		
	display = ctxt.display;
	tpic = display.newimage(Rect(zp, (winsz.x,winsz.y)), Draw->RGB24, 0, Draw->White);
	if (freqflag)
		fpic = display.newimage(Rect(zp, (winsz.x,winsz.y)), Draw->RGB24, 0, Draw->White);
	tkclient->startinput(top, "ptr" :: "kbd" :: nil);
	tkclient->onscreen(top, nil);
	spawn timer(tick);
	for(;;) alt {
	s := <-ctl or
	s = <-top.ctxt.ctl or
	s = <-top.wreq =>
		tkclient->wmctl(top, s);
		(ne, evt) := sys->tokenize(s," ");
		if (ne == 0)
			continue;
		case hd evt {
		"size" or "move" =>
			stoptimer = 1;
		"!size" =>
			if (hd tl evt != ".")
				break;
			rest:= int tk->cmd(top, ".cf cget  -actheight") +
				int tk->cmd(top, ".Wm_t cget  -actheight") +
				int tk->cmd(top, ".f cget  -actheight") + 2;
			newx:= int tk->cmd(top, ". cget  -actwidth");
			newy:= int tk->cmd(top, ". cget  -actheight") - rest;
			if(0) sys->print("!size: %d,%d -> %d,%d\n", winsz.x, winsz.y, newx, newy);
			if (newx > 0 && winsz.x != newx)
				winsz.x = newx;
			if (newy > 0 && winsz.y != newy)
				winsz.y = newy;
			stoptimer = 0;
		"!reshape" =>
			;
		"!move" =>
			stoptimer = 0;
		}
#		sys->print ("# ");
#		for (e:=0; e < ne; e++){
#			sys->print ("%s ", hd evt);
#			evt = tl evt;
#		}
#		sys->print ("\n");

	p := <-top.ctxt.ptr =>
		tk->pointer(top, *p);
	c := <-top.ctxt.kbd =>
		tk->keyboard(top, c);

	press := <-ccmd =>
		(nil,cmds) := sys->tokenize(press," ");
		if(cmds==nil) 
			continue;
		case hd cmds {
		"but1"=>
			x := int(hd tl cmds);
			y := int(hd tl cmds);
			sys->print("cmd (%d,%d)\n", x, y);
		"new" =>
			newchans:= int(tk->cmd(top,".cf.c get"));
			newrate:= int(tk->cmd(top,".cf.r get"));
			newfps:= int(tk->cmd(top,".cf.f get"));
			newgdiv:= int(tk->cmd(top,".cf.g get"));
			if (newchans > 0)
				chans = newchans;
			if (newrate > 0)
				rate = newrate;
			if (newfps > 0)
				fps = newfps;
			if (newgdiv > 0)
				gdiv = newgdiv;
		"freq" =>
			freqflag = !freqflag;
			if (!freqflag){
				fpic = display.newimage(Rect(zp, zp), Draw->RGB24, 0, Draw->White);
				tk->putimage(top, ".f", fpic, nil);
			}
		}
	<-tick =>
			nsamples = (rate * chans) / fps;
			r := readsample(fdin, nsamples);
			if (len r < winsz.x){
				if (0) sys->fprint(sys->fildes(2), "warning: enough data so skipping tick\n");
				break;
			}

			drawpic(top, ".t", tpic, r);
			if (freqflag){
				# ns: must be 2^n
				n:= int (math->log(real len r)/math->log(2.0) - 1.0);
				ns:= int math->pow(2.0, real n);
				(c,d):=calcfft(r[0:ns]);
				drawpic(top, ".f", fpic, cmodule(c[0:ns],d[0:ns]));
			}
	}
}

drawpic(top: ref Tk->Toplevel, picname: string, pic: ref Image, b: array of real)
{
	pic = display.newimage(Rect(zp, (winsz.x,winsz.y)), Draw->RGB24, 0, Draw->White);
	grid (picname, pic, winsz.x/gdiv, winsz.y/gdiv);
	
	if(chans == 2){
		pic.poly(real2point(b,0), Draw->Enddisc, Draw->Enddisc, 0, display.color(Draw->Red), zp);
		pic.poly(real2point(b,1), Draw->Enddisc, Draw->Enddisc, 0, display.color(Draw->Blue), zp);
	}else
		pic.poly(real2point(b,0), Draw->Enddisc, Draw->Enddisc, 0,  display.black, zp);

	tk->putimage(top, picname, pic, nil);
	tk->cmd(top, "update");
}

# maybe picinfo for legend would be more appropiate
grid(picname: string, pic: ref Image, dx, dy: int)
{
	x, y: int;
	gborder := display.color(16r777777ff);
	f := draw->Font.open(display, scofont);

	for(x=0; x <= winsz.x; x+=dx){
		if (x == dx*(winsz.x/dx/2))
			pic.line((x,0), (x, winsz.y), Draw->Endarrow, Draw->Endarrow, 0, display.black, zp);
		else
			pic.line((x,0), (x, winsz.y), Draw->Enddisc, Draw->Endsquare, 0, gborder, zp);
	}
	
	for(y=dy; y <= winsz.y; y+=dy){
		if (y == dy*(winsz.y/dy/2))
			pic.line((0,y), (winsz.x,y), Draw->Endarrow, Draw->Endarrow, 0, display.black, zp);
		else
			pic.line((0,y), (winsz.x,y), Draw->Enddisc, Draw->Endsquare, 0, gborder, zp);
	}
	
	samples := string nsamples;
	pic.text((winsz.x - 8*len samples, winsz.y/2-dy/2), display.black, zp, f, samples);
	pic.text((winsz.x - 10*len picname, winsz.y/2+dy/4), display.black, zp, f, picname);
}

cmodule(a,b: array of real) : array of real
{
	n:= len a;
	m:= array[n] of real;
	for (i:=0; i<n; i++){
		# minus makes plotting look as expected
		m[i] = - math->hypot(a[i], b[i]);
	}
	return m;
}

# (c,d) should use fft->ind2freq
calcfft(a: array of real): (array of real, array of real)
{
	n := len a;
	b:= array[n] of {* => 0.0};
	c:= array[n] of {* => 0.0};
	d:= array[n] of {* => 0.0};
	fft->fft_real(n, 0, a, b, c, d);
	return (c,d);
}

MAXAMP: con real 2 ** 15;
real2point(r: array of real, c: int): array of Point
{
	inc := len r / winsz.x;
	p := array[winsz.x + len r % winsz.x] of Point;
	
	j := 0;
	for(i := c; i < len r; i += inc){
		p[j] = Point(j,
			int((r[i]/MAXAMP)*(real winsz.y/2.0) + (real winsz.y/2.0)));
		j++;
	}
	return p[0:j];
}

# todo: revise relation between rate, samples, window size ...
readsample(fd: ref sys->FD, nsamples: int): array of real
{
	buf:= array[nsamples*2] of byte;
	b: array of byte;
	out:= array[nsamples] of real;
	nb := sys->read(fd, buf, len buf);
	if (nb < 0)
		raise "read: fail";

	if (outflag)
		sys->write(sys->fildes(1), buf, nb);
	b=buf[0:nb];
	for(i:=0;i<nb/2;i++){
		out[i] = real ((int b[1]<<24 | int b[0] << 16) >> 16);
		b = b[2:];
	}
	return out[0:i];
}

timer(tick: chan of int)
{
	for(;;){
		if (!stoptimer){
			sys->sleep(1000/fps);
			tick <-= 1;
		}
	}
}
