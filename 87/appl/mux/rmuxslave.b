implement Rmuxslave;

include "sys.m";
include "draw.m";
include "devpointer.m";

sys: Sys;
draw: Draw;
ptr: Devpointer;

FD, fprint: import sys;
Context, Display: import draw;

include "ir.m";

stderr: ref FD;

Rmuxslave: module
{
	init: fn(ctxt: ref Context, args: list of string);
};

refresh(display:ref Display)
{
	display.startrefresh();
}

init(nil: ref Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	ptr = load Devpointer Devpointer->PATH;
	stderr = sys->fildes(2);

	if(len args < 3){
		fprint(stderr, "usage: rmuxslave -s3 command args\n");
		return;
	}

	args = tl args;
	arg := hd args;
	if(len arg<2 || arg[0:2]!="-s"){
		fprint(stderr, "usage: rmuxslave -s3 command args\n");
		return;
	}
	screenid := int arg[2:len arg];
	args = tl args;

	file := hd args + ".dis";
	cmd := load Rmuxslave file;
	if(cmd == nil)
		cmd = load Rmuxslave "/dis/mux/"+file;
	if(cmd == nil){
		fprint(stderr, "rmuxslave: can't load %s: %r\n", hd args);
		return;
	}

	display := Display.allocate(nil);
	if(display == nil){
		fprint(stderr, "can't initialize display: %r\n");
		return;
	}
	spawn refresh(display);
	screen := display.publicscreen(screenid);
	if(screen == nil){
		fprint(stderr, "can't establish screen id %d: %r\n", screenid);
		return;
	}

	cir := recvfromfile("mux.cir");
	ckbd := recvfromfile("mux.ckbd");
	cptr:= recvptrfromfile("mux.cptr");
	ctoappl := recvfromfile("mux.ctoappl");
	ctomux := sendtofile("mux.ctomux");
	if(cir==nil || ckbd==nil || ctoappl==nil || ctomux==nil){
		# BUG: need to shut down slaves cleanly
		return;
	}

	ctxt := ref Context;
	ctxt.screen = screen;
	ctxt.display = display;
	ctxt.cir = cir;
	ctxt.ckbd = ckbd;
	ctxt.cptr = cptr;
	ctxt.ctoappl = ctoappl;
	ctxt.ctomux = ctomux;
	
	spawn cmd->init(ctxt, args);
}

sendtofile(file: string): chan of int
{
	fd := sys->open("/n/client/chan/"+file, sys->OWRITE);
	if(fd == nil){
		fprint(stderr, "rmuxslave can't open %s: %r\n", file);
		return nil;
	}
	source := chan of int;
	spawn sender(fd, source);
	return source;
}

recvfromfile(file: string): chan of int
{
	fd := sys->open("/n/client/chan/"+file, sys->OREAD);
	if(fd == nil){
		fprint(stderr, "rmuxslave can't open %s: %r\n", file);
		return nil;
	}
	dest := chan of int;
	spawn receiver(fd, dest);
	return dest;
}

recvptrfromfile(file: string): chan of ref Draw->Pointer
{
	fd := sys->open("/n/client/chan/"+file, sys->OREAD);
	if(fd == nil){
		fprint(stderr, "rmuxslave can't open %s: %r\n", file);
		return nil;
	}
	dest := chan of ref Draw->Pointer;
	spawn receiverptr(fd, dest);
	return dest;
}

sender(fd: ref FD, source: chan of int)
{
	msg:= array[1] of byte;

	for(;;){
		msg[0] = byte <-source;
		if(sys->write(fd, msg, 1) != 1){
			fprint(stderr, "rmuxslave: write error: %r\n");
			return;
		}
	}
}

receiver(fd: ref FD, dest: chan of int)
{
	msg:= array[1] of byte;

	for(;;){
		if(sys->read(fd, msg, 1) != 1){
			fprint(stderr, "rmuxslave: read error: %r\n");
			return;
		}
		dest <-= int msg[0];
	}
}

receiverptr(fd: ref FD, dest: chan of ref Draw->Pointer)
{
	msg:= array[Devpointer->Size] of byte;

	for(;;){
		if(sys->read(fd, msg, len msg) != len msg){
			fprint(stderr, "rmuxslave: read error: %r\n");
			return;
		}
		dest <-= ptr->bytes2ptr(msg);
	}
}
