Wmclient: module
{
	PATH:		con "rioclient.dis";

	Resize,
	Hide,
	Help,
	OK,
	Popup,
	Plain:		con 1 << iota;
	Appl:		con Resize | Hide;

	init:		fn();
	makedrawcontext: fn(): ref Draw->Context;
	window:		fn(ctxt: ref Draw->Context, title: string, buts: int): ref Window;
	snarfput:		fn(buf: string);
	snarfget:		fn(): string;

	Window: adt{
		display:	ref Draw->Display;
		r: Draw->Rect;		# full rectangle of window, including titlebar.
		image: ref Draw->Image;
		displayr: Draw->Rect;
		ctxt: ref Draw->Wmcontext;
		bd:		int;
		focused:	int;
		ctl:		chan of string;

		# private from here:
		tbsize: 	Draw->Point;			# size requested by titlebar.
		tbrect:	Draw->Rect;
		screen:	ref Draw->Screen;
		buttons:	int;
		ptrfocus:	int;
		saved:	Draw->Point;			# saved origin before task

		startinput:	fn(w: self ref Window, devs: list of string);
		wmctl:	fn(w: self ref Window, request: string): string;
		settitle:	fn(w: self ref Window, name: string): string;
		reshape:	fn(w: self ref Window, r: Draw->Rect);
		onscreen:	fn(w: self ref Window, how: string);
		screenr:	fn(w: self ref Window, sr: Draw->Rect): Draw->Rect;
		imager:	fn(w: self ref Window, ir: Draw->Rect): Draw->Rect;
		pointer:	fn(w: self ref Window, p: Draw->Pointer): int;
	};

};
