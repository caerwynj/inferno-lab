implement Rmux;

include "sys.m";
include "draw.m";
include "devpointer.m";

sys: Sys;
draw: Draw;
ptr: Devpointer;

FD, FileIO, sprint, fprint: import sys;
Context, AMexit: import draw;
pgrp: int;

include "ir.m";

stderr: ref FD;

Rmux: module
{
	init: fn(ctxt: ref Context, argc: list of string);
};

init(ctxt: ref Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	ptr = load Devpointer Devpointer->PATH;
	rcmd := load Rmux "/dis/rcmd.dis";

	stderr = sys->fildes(2);

	if(len args < 2){
		fprint(stderr, "usage: rmux machine command: %r\n");
		ctxt.ctomux <-= AMexit;
		return;
	}

	if(rcmd == nil){
		fprint(stderr, "rmux: can't load rcmd: %r\n");
		ctxt.ctomux <-= AMexit;
		return;
	}

	sys->pctl(sys->FORKNS, nil);
	pgrp = sys->pctl(sys->NEWPGRP, nil);

	io1 := sendtofile("mux.cir", ctxt.cir);
	io2 := sendtofile("mux.ckbd", ctxt.ckbd);
	io3 := sendptrtofile("mux.cptr", ctxt.cptr);
	io4 := sendtofile("mux.ctoappl", ctxt.ctoappl);
	io5 := recvfromfile("mux.ctomux", ctxt.ctomux);
	if(io1==nil || io2==nil || io4==nil || io5==nil){
		# BUG: need to shut down slaves cleanly
		ctxt.ctomux <-= AMexit;
		return;
	}

	screenid := sprint("-s%d", ctxt.screen.id);
	rcmd->init(ctxt, "rcmd" :: "hati" :: "rmuxslave" :: screenid :: tl args);
}

makefile(file: string): ref FileIO
{
	sys->bind("#s", "/chan", Sys->MBEFORE);
	io := sys->file2chan("/chan", file);
	if(io == nil){
		fprint(stderr, "rmux: can't establish %s: %r\n", file);
		return nil;
	}
	return io;
}

sendtofile(file: string, source: chan of int): ref FileIO
{
	io := makefile(file);
	if(io == nil)
		return nil;
	spawn sender(io, source);
	return io;
}

sendptrtofile(file: string, source: chan of ref Draw->Pointer): ref FileIO
{
	io := makefile(file);
	if(io == nil)
		return nil;
	spawn senderptr(io, source);
	return io;
}

recvfromfile(file: string, dest: chan of int): ref FileIO
{
	io := makefile(file);
	if(io == nil)
		return nil;
	spawn receiver(io, dest);
	return io;
}

sender(io: ref FileIO, source: chan of int)
{
	msg:= array[1] of byte;

	for(;;){
		msg[0] = byte <-source;
		(off, nbytes, fid, rc) := <-io.read;
		if(nbytes == 1)
			rc <-= (msg, nil);
		else
			rc <-= (nil, "incorrect byte count");
	}
}

senderptr(io: ref FileIO, source: chan of ref Draw->Pointer)
{
	for(;;){
		msg := ptr->ptr2bytes(<-source);
		(off, nbytes, fid, rc) := <-io.read;
		if(nbytes == len msg)
			rc <-= (msg, nil);
		else
			rc <-= (nil, "incorrect byte count");
	}
}

receiver(io: ref FileIO, dest: chan of int)
{

	for(;;){
		(off, msg, fid, wc) := <-io.write;
		if(len msg == 1){
			wc <-= (1, nil);
			dest <-= int msg[0];
			if(int msg[0] == Draw->AMexit){
				shutdown();
				exit;
			}
		}else
			wc <-= (0, "incorrect byte count");
	}
}

shutdown()
{
	fname := sys->sprint("#p/%d/ctl", pgrp);
	if ((fdesc := sys->open(fname, sys->OWRITE)) != nil)
		sys->write(fdesc, array of byte "killgrp\n", 8);
}
