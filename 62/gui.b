implement Synth;

include "sys.m";
	sys: Sys;
	sprint: import sys;

include "draw.m";
	draw: Draw;
	Rect, Display, Image, Point: import draw;
	ctxt: ref Draw->Context;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "dialog.m";
	dialog: Dialog;

include "selectfile.m";
	selectfile: Selectfile;

include "sequencer.m";
	sequencer: Sequencer;
	Inst, Source, Sample, Control, BLOCK: import sequencer;
	waveloop, fm, poly, lfo, delay, 
	adsr, onepole, onezero, twopole, twozero, mixer: import sequencer;
	CFREQ, CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN, 
	CRELEASE, CDELAY, CVOICE, CMIX, CHIGH, CLOW,
	CPOLE, CZERO, CTUNE: import sequencer;

Synth: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Stopped, Playing: con iota;

playctl: chan of string;
scope: ref Image;
display: ref Display;
top: ref Toplevel;
maininst: ref Inst;

task_cfg := array[] of {
	"panel .c -width 248 -height 248",
	"frame .b",
	"button .b.File -text File -command {send cmd file}",
	"button .b.Stop -text Stop -command {send cmd stop}",
	"button .b.Play -text Play -command {send cmd play}",
	"frame .f",
	"label .f.file -text {File:}",
	"label .f.name",
	"pack .f.file .f.name -side left",
	"pack .b.File .b.Stop .b.Play -side left",
	"pack .f -fill x",
	"pack .b -anchor w",
	"pack .c ",
	"frame .g",
	"pack .g -fill x -fill y",
	"update",
};

init(xctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	dialog = load Dialog Dialog->PATH;
	selectfile = load Selectfile Selectfile->PATH;
	sequencer = load Sequencer Sequencer->PATH;

	ctxt = xctxt;
	display = ctxt.display;
	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	dialog->init();
	selectfile->init();
	sequencer->modinit();

	playctl = chan of string;
	(t, menubut)  := tkclient->toplevel(ctxt, "", "Mpeg Player", Tkclient->Appl);
	top = t;
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for(i := 0; i < len task_cfg; i++)
		tk->cmd(t, task_cfg[i]);

	tk->cmd(t, "update");
	scope = ctxt.display.newimage(Rect((0,0),(248,248)), Draw->GREY8, 0, Draw->White);
	tk->putimage(t, ".c", scope, nil);

	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr"::nil);
	fname := "";
	state := Stopped;
	maininst = Inst.mk(nil, prodigy);

	for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq =>
		tkclient->wmctl(t, s);
	menu := <-menubut =>
		if(menu == "exit") {
			if(state == Playing) {
				playctl <-= "stop";
			}
			kill(sys->pctl(0,nil), "killgrp");
			return;
		}
		tkclient->wmctl(t, menu);
	press := <-cmd =>
		case press {
		"file" =>
			pat := list of {
				"*.ski"
			};
			fname = selectfile->filename(ctxt, nil, "Locate Skini File", pat, "");
			if(fname != nil) {
				tk->cmd(t, ".f.name configure -text {"+fname+"}");
				tk->cmd(t, "update");
			}
		"play" =>
			if(state != Playing && fname != nil)
				spawn sequencer->play(fname, playctl, maininst);
			state = Playing;
		* =>
			# Stop & Pause
			playctl <-= "stop";
			state = Stopped;
		}
	}
}

scopedraw(nil: Source, c: Sample, nil: Control)
{
	for(;;) alt {
	(a, nil) := <- c =>
		if(len a < BLOCK)
			continue;
		scope.draw(scope.r, display.white, nil, (0,0));
		scope.poly(real2point(a), Draw->Enddisc, 
			Draw->Enddisc, 0, display.black, (0,0));
		tk->putimage(top, ".c", scope, nil);
		tk->cmd(top, "update");
	}
}

real2point(r: array of real): array of Point
{
	p := array[248] of Point;
	n := len r / 248;
	j := 0;
	for(i := 0; i < len r; i +=n){
		p[j] = Point(j, int(r[i]*124.0 + 124.0));
		j++;
	}
	return p;
}

prodigy(nil: Source, c: Sample, ctl: Control)
{
	inst := array[4] of {* => Inst.mk(array[2] of {* => Inst.mk(nil, fm)}, poly)};
	voice := 0;
	mix := Inst.mk(inst, mixer);
	wrc := chan of array of real;
	delay1 := Inst.mk(nil, delay);
	spawn knob(delay1.ctl, "delay1", CDELAY, 0.0, 1.0, 0.01);
	spawn knob(delay1.ctl, "delay1mix", CMIX, 0.0, 1.0, 0.01);
	delay2 := Inst.mk(nil, delay);
	spawn knob(delay2.ctl, "delay2", CDELAY, 0.0, 1.0, 0.01);
	spawn knob(delay2.ctl, "delay2mix", CMIX, 0.0, 1.0, 0.01);
	filt1 := Inst.mk(nil, onepole);
	spawn knob(filt1.ctl, "filt1pole", CPOLE, -1.0, 1.0, 0.01);
	filt2 := Inst.mk(nil, twopole);
	spawn knob(filt2.ctl, "filt2freq", CFREQ, 1.0, 1000.0, 1.0);
	lfo1 := Inst.mk(nil, lfo);
	lfo1.ctl <-= (CFREQ, 0.7);
	lfo2 := Inst.mk(nil, lfo);
	lfo2.ctl <-= (CFREQ, 0.4);
	lfo2.ctl <-= (CHIGH, 0.2);
	lfo2.ctl <-= (CLOW, 0.1);
	oscope := Inst.mk(nil, scopedraw);
	tot := 0;

	for(;;) alt {
	(a, rc ) := <-c =>
		tot += len a;
		if(tot >= BLOCK){
			t := array[1] of real;
			lfo1.c <-= (t, wrc);
			t = <-wrc;
#			filt1.ctl <-= (CFREQ, t[0]);
			lfo2.c <-= (t, wrc);
			t =<- wrc;
#			delay2.ctl <-= (CDELAY, t[0]);
			tot -= BLOCK;
		}
		mix.c <-= (a, wrc);
		oscope.c <-= (a, nil);
		filt1.c <-= (<-wrc, wrc);
		filt2.c <-= (<-wrc, wrc);
		delay1.c <-= (<-wrc, wrc);
		delay2.c <-= (<-wrc, wrc);
		rc <-= <-wrc;
	(m, n) := <-ctl =>
		case m {
		CKEYON =>
			inst[voice].ctl <-= (m, n);
		CKEYOFF =>
			inst[voice].ctl <-= (m, n);
		CVOICE =>
			voice = int n;
			# two note polyphony for each voice using 'fm' as the generator
			if(inst[voice] == nil)
				inst[voice] = Inst.mk(array[2] of {* => Inst.mk(nil, fm)}, poly);
		}
	}
}

knobcnt := 0;
rowcnt := 0;
knob(ctl: Control, name: string, cmsg: int, low, high, res: real)
{
	if(!(knobcnt%4)){
		tk->cmd(top, sprint("grid columninsert .g end"));
		rowcnt++;
	}
	cname := sprint("%s%d", name, knobcnt);
	pchan := chan of string;
	tk->namechan(top, pchan, cname);
	widget := sprint(".g.z%d", knobcnt);
	tk->cmd(top, sprint("scale %s -orient horizontal -label %s -from %g -to %g -resolution %g -command {send %s x}", widget, name, low, high, res, cname));
	tk->cmd(top, sprint("grid %s -column %d -row %d -in .g", widget, knobcnt%4, rowcnt));
	tk->cmd(top, "update");
	knobcnt++;
	for(;;){
		<-pchan;
		x := real tk->cmd(top, widget + " get");
		ctl <-= (cmsg, x);
	}
}

kill(pid: int, note: string): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", note) < 0)
		return -1;
	return 0;
}
