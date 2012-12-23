implement View;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Context, Rect, Point, Display, Screen, Image: import draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "img.m";
	img: Img;
	ByteSource, ImageSource, MaskedImage: import img;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"tkclient.m";
	tkclient: Tkclient;

include "selectfile.m";
	selectfile: Selectfile;

include	"arg.m";

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

stderr: ref Sys->FD;
display: ref Display;
x := 25;
y := 25;
img_patterns: list of string;
plumbed := 0;
background: ref Image;

View: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
	spawn realinit(ctxt, argv);
}

realinit(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if (ctxt == nil) {
		sys->fprint(sys->fildes(2), "view: no window context\n");
		raise "fail:bad context";
	}
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	selectfile = load Selectfile Selectfile->PATH;
	img = load Img Img->PATH;
	img->init(ctxt);

	sys->pctl(Sys->NEWPGRP, nil);
	tkclient->init();
	selectfile->init();

	stderr = sys->fildes(2);
	display = ctxt.display;
	background = display.color(16r222222ff);

	arg := load Arg Arg->PATH;
	if(arg == nil)
		badload(Arg->PATH);

	img_patterns = list of {
		"*.bit (Compressed image files)",
		"*.gif (GIF image files)",
		"*.jpg (JPEG image files)",
		"*.jpeg (JPEG image files)",
		"*.png (PNG image files)",
		"*.xbm (X Bitmap image files)"
		};

	bufio = load Bufio Bufio->PATH;
	if(bufio == nil)
		badload(Bufio->PATH);


	arg->init(argv);
	errdiff := 1;
	while((c := arg->opt()) != 0)
		case c {
		'f' =>
			errdiff = 0;
		'i' =>
			if(!plumbed){
				plumbmsg = load Plumbmsg Plumbmsg->PATH;
				if(plumbmsg != nil && plumbmsg->init(1, "view", 1000) >= 0)
					plumbed = 1;
			}
		}
	argv = arg->argv();
	arg = nil;
	if(argv == nil && !plumbed){
		f := selectfile->filename(ctxt, nil, "View file name", img_patterns, nil);
		if(f == "") {
			#spawn view(nil, nil, "");
			return;
		}
		argv = f :: nil;
	}


	for(;;){
		file: string;
		if(argv != nil){
			file = hd argv;
			argv = tl argv;
			if(file == "-f"){
				errdiff = 0;
				continue;
			}
		}else if(plumbed){
			file = plumbfile();
			if(file == nil)
				break;
			errdiff = 1;	# set this from attributes?
		}else
			break;

		(ims, masks, err) := readimages(file, errdiff);

		if(ims == nil)
			sys->fprint(stderr, "view: can't read %s: %s\n", file, err);
		else
			spawn view(ctxt, ims, masks, file);
	}
}

badload(s: string)
{
	sys->fprint(stderr, "view: can't load %s: %r\n", s);
	raise "fail:load";
}

readimages(file: string, errdiff: int) : (array of ref Image, array of ref Image, string)
{
	im := display.open(file);

	if(im != nil)
		return (array[1] of {im}, array[1] of ref Image, nil);

	fd := bufio->open(file, Sys->OREAD);
	if(fd == nil)
		return (nil, nil, sys->sprint("%r"));

	data := array[1024] of byte;
	i := 0;
	while((b := fd.getb()) != Bufio->EOF){
		data[i++] = byte b;
		if (i == len data)
			data = (array[len data * 2] of byte)[0:] = data[0:];
	}
	bs := ref ByteSource(data[0:i], 1, filetype(file, fd), 0, i);
	is := ImageSource.new(bs, 0, 0);
	(ans, mim) := is.getmim();
	if(ans == Img->Mimerror){
		return (nil, nil, "error");
	}
	ims := array[1] of ref Image;
	masks := array[1] of ref Image;
	ims[0] = mim.im;
	masks[0] = mim.mask;
	return (ims, masks, nil);
}

viewcfg := array[] of {
	"panel .p",
	"menu .m",
	".m add command -label Open -command {send cmd open}",
	".m add command -label Grab -command {send cmd grab} -state disabled",
	".m add command -label Save -command {send cmd save}",
	"pack .p -side bottom -fill both -expand 1",
	"bind .p <Button-3> {send cmd but3 %X %Y}",
	"bind .p <Motion-Button-3> {}",
	"bind .p <ButtonRelease-3> {}",
	"bind .p <Button-1> {send but1 %X %Y}",
};

DT: con 250;

timer(dt: int, ticks, pidc: chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for(;;){
		sys->sleep(dt);
		ticks <-= 1;
	}
}

view(ctxt: ref Context, ims, masks: array of ref Image, file: string)
{
	file = lastcomponent(file);
	(t, titlechan) := tkclient->toplevel(ctxt, "", "view: "+file, Tkclient->Appl);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	but1 := chan of string;
	tk->namechan(t, but1, "but1");

	for (c:=0; c<len viewcfg; c++)
		tk->cmd(t, viewcfg[c]);
	tk->cmd(t, "update");

	image := display.newimage(ims[0].r, ims[0].chans, 0, Draw->White);
	if (image == nil) {
		sys->fprint(stderr, "view: can't create image: %r\n");
		return;
	}
	imconfig(t, image);
	image.draw(image.r, ims[0], masks[0], ims[0].r.min);
	tk->putimage(t, ".p", image, nil);
	tk->cmd(t, "update");

	pid := -1;
	ticks := chan of int;
	if(len ims > 1){
		pidc := chan of int;
		spawn timer(DT, ticks, pidc);
		pid = <-pidc;
	}
	imno := 0;
	grabbing := 0;
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);


	for(;;) alt{
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-titlechan =>
		tkclient->wmctl(t, s);

	<-ticks =>
		if(masks[imno] != nil)
			paneldraw(t, image, image.r, background, nil, image.r.min);
		++imno;
		if(imno >= len ims)
			imno = 0;
		paneldraw(t, image, ims[imno].r, ims[imno], masks[imno], ims[imno].r.min);
		tk->cmd(t, "update");

	s := <-cmd =>
		(nil, l) := sys->tokenize(s, " ");
		case (hd l) {
		"open" =>
			spawn open(ctxt, t);
		"grab" =>
			tk->cmd(t, "cursor -bitmap cursor.drag; grab set .p");
			grabbing = 1;
		"save" =>
			patterns := list of {
				"*.bit (Inferno image files)",
				"*.gif (GIF image files)",
				"*.jpg (JPEG image files)",
				"* (All files)"
			};
			f := selectfile->filename(ctxt, t.image, "Save file name",
				patterns, nil);
			if(f != "") {
				fd := sys->create(f, Sys->OWRITE, 8r664);
				if(fd != nil) 
					display.writeimage(fd, ims[0]);
			}
		"but3" =>
			if(!grabbing) {
				xx := int hd tl l - 50;
				yy := int hd tl tl l - int tk->cmd(t, ".m yposition 0") - 10;
				tk->cmd(t, ".m activate 0; .m post "+string xx+" "+string yy+
					"; grab set .m; update");
			}
		}
	s := <- but1 =>
			if(grabbing) {
				(nil, l) := sys->tokenize(s, " ");
				xx := int hd l;
				yy := int hd tl l;
#				grabtop := tk->intop(ctxt.screen, xx, yy);
#				if(grabtop != nil) {
#					cim := grabtop.image;
#					imr := Rect((0,0), (cim.r.dx(), cim.r.dy()));
#					image = display.newimage(imr, cim.chans, 0, draw->White);
#					if(image == nil){
#						sys->fprint(stderr, "view: can't allocate image\n");
#						exit;
#					}
#					image.draw(imr, cim, nil, cim.r.min);
#					tk->cmd(t, ".Wm_t.title configure -text {View: grabbed}");
#					imconfig(t, image);
#					tk->putimage(t, ".p", image, nil);
#					tk->cmd(t, "update");
#					# Would be nicer if this could be spun off cleanly
#					ims = array[1] of {image};
#					masks = array[1] of ref Image;
#					imno = 0;
#					grabtop = nil;
#					cim = nil;
#				}
				tk->cmd(t, "cursor -default; grab release .p");
				grabbing = 0;
			}
	}
}

open(ctxt: ref Context, t: ref tk->Toplevel)
{
	f := selectfile->filename(ctxt, t.image, "View file name", img_patterns, nil);
	t = nil;
	if(f != "") {
		(ims, masks, err) := readimages(f, 1);
		if(ims == nil)
			sys->fprint(stderr, "view: can't read %s: %s\n", f, err);
		else
			view(ctxt, ims, masks, f);
	}
}

lastcomponent(path: string) : string
{
	for(k:=len path-2; k>=0; k--)
		if(path[k] == '/'){
			path = path[k+1:];
			break;
		}
	return path;
}

imconfig(t: ref Toplevel, im: ref Draw->Image)
{
	width := im.r.dx();
	height := im.r.dy();
	tk->cmd(t, ".p configure -width " + string width
		+ " -height " + string height + "; update");
}

plumbfile(): string
{
	if(!plumbed)
		return nil;
	for(;;){
		msg := Msg.recv();
		if(msg == nil){
			sys->print("view: can't read /chan/plumb.view: %r\n");
			return nil;
		}
		if(msg.kind != "text"){
			sys->print("view: can't interpret '%s' kind of message\n", msg.kind);
			continue;
		}
		file := string msg.data;
		if(len file>0 && file[0]!='/' && len msg.dir>0){
			if(msg.dir[len msg.dir-1] == '/')
				file = msg.dir+file;
			else
				file = msg.dir+"/"+file;
		}
		return file;
	}
}


GIF, JPG, PIC, PNG, XBM: con iota;


filetype(file: string, fd: ref Iobuf): int
{
	fd.seek(big 0, 0);
	# sniff the header looking for a magic number
	buf := array[20] of byte;
	if(fd.read(buf, len buf) != len buf)
		return Img->UnknownType;
	fd.seek(big 0, 0);
	if(string buf[0:6]=="GIF87a" || string buf[0:6]=="GIF89a")
		return Img->ImageGif;
#	if(string buf[0:5] == "TYPE=")
#		return loadmod(PIC);
	jpmagic := array[] of {byte 16rFF, byte 16rD8, byte 16rFF, byte 16rE0,
		byte 0, byte 0, byte 'J', byte 'F', byte 'I', byte 'F', byte 0};
	if(eqbytes(buf, jpmagic))
		return Img->ImageJpeg;
	pngmagic := array[] of {byte 137, byte 80, byte 78, byte 71, byte 13, byte 10, byte 26, byte 10};
	if(eqbytes(buf, pngmagic))
		return Img->ImagePng;
	if(string buf[0:7] == "#define")
		return Img->ImageXBit;
	return Img->UnknownType;
}

eqbytes(buf, magic: array of byte): int
{
	for(i:=0; i<len magic; i++)
		if(magic[i]>byte 0 && buf[i]!=magic[i])
			return 0;
	return i == len magic;
}


paneldraw(t: ref Tk->Toplevel, dst: ref Image, r: Rect, src, mask: ref Image, p: Point)
{
	dst.draw(r, src, mask, p);
	s := sys->sprint(".p dirty %d %d %d %d", r.min.x, r.min.y, r.max.x, r.max.y);
	tk->cmd(t, s);
}
