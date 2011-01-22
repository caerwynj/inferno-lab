Draw: module
{
	PATH:	con	"$Draw";

	# predefined colors; pass to Display.color
	Black:	con 255;
	Blue:	con 201;
	Red:	con 15;
	Yellow:	con 3;
	Green:	con 192;
	White:	con 0;

	# end styles for line
	Endsquare:	con 0;
	Enddisc:	con 1;
	Endarrow:	con 2;

	# flush control
	Flushoff:	con 0;
	Flushon:	con 1;
	Flushnow:	con 2;

	# Coordinate of a pixel on display
	Point: adt
	{
		x:	int;
		y:	int;

		# arithmetic
		add:	fn(p: self Point, q: Point): Point;
		sub:	fn(p: self Point, q: Point): Point;
		mul:	fn(p: self Point, i: int): Point;
		div:	fn(p: self Point, i: int): Point;
		# equality
		eq:	fn(p: self Point, q: Point): int;
		# inside rectangle
		in:	fn(p: self Point, r: Rect): int;
	};

	# Rectangle of pixels on the display; min <= max
	Rect: adt
	{
		min:	Point;	# upper left corner
		max:	Point;	# lower right corner

		# make sure min <= max
		canon:		fn(r: self Rect): Rect;
		# extent
		dx:		fn(r: self Rect): int;
		dy:		fn(r: self Rect): int;
		# equality
		eq:		fn(r: self Rect, s: Rect): int;
		# intersection and clipping
		Xrect:		fn(r: self Rect, s: Rect): int;
		inrect:		fn(r: self Rect, s: Rect): int;
		clip:		fn(r: self Rect, s: Rect): (Rect, int);
		contains:	fn(r: self Rect, p: Point): int;
		# arithmetic
		addpt:		fn(r: self Rect, p: Point): Rect;
		subpt:		fn(r: self Rect, p: Point): Rect;
		inset:		fn(r: self Rect, n: int): Rect;
	};

	# a picture; if made by Screen.newwindow, a window.  always attached to a Display
	Image: adt
	{
		# these data are local copies, but repl and clipr
		# are monitored by the runtime and may be modified as desired.
		r:	Rect;		# rectangle in data area, local coords
		clipr:	Rect;		# clipping region
		ldepth:	int;		# log base 2 of number of bits per pixel
		repl:	int;		# whether data area replicates to tile the plane
		display:	ref Display; # where Image resides
		screen:		ref Screen;	 # nil if not window

		# graphics operators
		draw:		fn(dst: self ref Image, r: Rect, src: ref Image, mask: ref Image, p: Point);
		gendraw:		fn(dst: self ref Image, r: Rect, src: ref Image, p0: Point, mask: ref Image, p1: Point);
		line:		fn(dst: self ref Image, p0,p1: Point, end0,end1,radius: int, src: ref Image, sp: Point);
		poly:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point);
		bezspline:		fn(dst: self ref Image, p: array of Point, end0,end1,radius: int, src: ref Image, sp: Point);
		fillpoly:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point);
		fillbezspline:	fn(dst: self ref Image, p: array of Point, wind: int, src: ref Image, sp: Point);
		ellipse:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point);
		fillellipse:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point);
		arc:	fn(dst: self ref Image, c: Point, a, b, thick: int, src: ref Image, sp: Point, alpha, phi: int);
		fillarc:	fn(dst: self ref Image, c: Point, a, b: int, src: ref Image, sp: Point, alpha, phi: int);
		bezier:	fn(dst: self ref Image, a,b,c,d: Point, end0,end1,radius: int, src: ref Image, sp: Point);
		fillbezier:	fn(dst: self ref Image, a,b,c,d: Point, wind:int, src: ref Image, sp: Point);
		text:		fn(dst: self ref Image, p: Point, src: ref Image, sp: Point, font: ref Font, str: string): Point;
		arrow:		fn(a,b,c: int): int;
		# direct access to pixels
		readpixels:	fn(src: self ref Image, r: Rect, data: array of byte): int;
		writepixels:	fn(dst: self ref Image, r: Rect, data: array of byte): int;
		# windowing
		top:		fn(win: self ref Image);
		bottom:		fn(win: self ref Image);
		flush:		fn(win: self ref Image, func: int);
		origin:		fn(win: self ref Image, log, scr: Point): int;
	};

	# a frame buffer, holding a connection to /dev/draw
	Display: adt
	{
		image:	ref Image;	# holds the contents of the display
		ones:	ref Image;	# predefined mask
		zeros:	ref Image;	# predefined mask

		# allocate and start refresh slave
		allocate:	fn(dev: string): ref Display;
		startrefresh:	fn(d: self ref Display);
		# attach to existing Screen
		publicscreen:	fn(d: self ref Display, id: int): ref Screen;
		# image creation
		newimage:	fn(d: self ref Display, r: Rect, ldepth, repl, color: int): ref Image;
		color:		fn(d: self ref Display, color: int): ref Image;
		rgb:		fn(d: self ref Display, r, g, b: int): ref Image;
		# I/O to files
		open:		fn(d: self ref Display, name: string): ref Image;
		readimage:	fn(d: self ref Display, fd: ref Sys->FD): ref Image;
		writeimage:	fn(d: self ref Display, fd: ref Sys->FD, i: ref Image): int;
		# color map
		rgb2cmap:	fn(d: self ref Display, r, g, b: int): int;
		cmap2rgb:	fn(d: self ref Display, c: int): (int, int, int);
		cursor:		fn(d: self ref Display, i: ref Image, p: ref Point): int;
	};

	# a mapping between characters and pictures; always attached to a Display
	Font: adt
	{
		name:	string;		# *default* or a file name (this may change)
		height:	int;		# interline spacing of font
		ascent:	int;		# distance from baseline to top
		display:	ref Display;	# where Font resides

		# read from file or construct from local description
		open:		fn(d: ref Display, name: string): ref Font;
		build:		fn(d: ref Display, name, desc: string): ref Font;
		# horizontal extent of string
		width:		fn(f: self ref Font, str:string): int;
	};

	# a collection of windows; always attached to a Display
	Screen: adt
	{
		id:		int;		# for export when public
		image:		ref Image;	# root of window tree
		fill:		ref Image;	# picture to use when repainting
		display:	ref Display;	# where Screen resides

		# create; see also Display.publicscreen
		allocate:	fn(image, fill: ref Image, public: int): ref Screen;
		# allocate a new window
		newwindow:	fn(screen: self ref Screen, r: Rect, color: int): ref Image;
		# make group of windows visible
		top:		fn(screen: self ref Screen, wins: array of ref Image);
	};

	# the state of a pointer device, e.g. a mouse
	Pointer: adt
	{
		buttons:	int;	# bits 1 2 4 ... represent state of buttons left to right; 1 means pressed
		xy:		Point;	# position
	};

	# From appl to mux
	AMexit:		con 10;		# application is exiting
	AMstartir:	con 11;		# application is ready to receive IR events
	AMstartkbd:	con 12;		# application is ready to receive keyboard characters
	AMstartptr:	con 13;		# application is ready to receive mouse events
	AMnewpin:	con 14;		# application needs a PIN

	# From mux to appl
	MAtop:		con 20;		# application should make all its windows visible

	Context: adt
	{
		screen: 	ref Screen;		# place to make windows
		display: 	ref Display;		# frame buffer on which windows reside
		cir: 		chan of int;		# incoming events from IR remote
		ckbd: 		chan of int;		# incoming characters from keyboard
		cptr: 		chan of ref Pointer;	# incoming stream of mouse positions
		ctoappl:	chan of int;		# commands from mux to application
		ctomux:		chan of int;		# commands from application to mux
	};
};
