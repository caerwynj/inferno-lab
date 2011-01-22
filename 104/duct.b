implement Duct;

#
# Duct - bi-directional 9P multiplexor
# Copyright (c) 2009 Eric Van Hensbergen <ericvh@gmail.com>
#

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	
include "styx.m";

Duct: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
	uplink: fn(infd: ref Sys->FD, outfd: ref Sys->FD, out: string, in:string);
};

# like stream, but respects 9P message boundaries
splice(infd: ref sys->FD, outfd: ref sys->FD, ctl: chan of int)
{
	buf := array[Styx->MAXRPC] of byte;
	
	ctl <-= sys->pctl(0, nil);

	while(1) {
		count := sys->readn(infd, buf, 4);
		if(count <= 0) {
			ctl <-= -1;
			return;
		}
		if(count < 4) {
			raise "short read of packet size";
		}
		
		size := (int buf[1] << 8) | int buf[0];
		size |= ((int buf[3] << 8) | int buf[2]) << 16;

		if(size > Styx->MAXRPC)
			raise "oversized packet";
		count = sys->readn(infd, buf[4:], size-4);
		if(count <= 0)
			return;		
		if(count < size-4) {
			raise "splice: short read of packet";
		}
		count = sys->write(outfd, buf, size);
		if(count < size) {
			sys->fprint(sys->fildes(2), "splice write returned: %d\n", count);
			raise "short write of packet";
		}
	}
}

# need a separate thread to do mount
mountit(infd: ref Sys->FD, in: string)
{
	if ( sys->mount( infd, nil, in, Sys->MREPL|Sys->MCREATE, nil) < 0 ) 
		raise "problem with mount";
	infd = nil;
}

cleanup(in: string)
{
	sys->unmount(nil, in);
	
	#mypid := sys->pctl(0, nil);
	#fd := sys->open("/prog/"+string mypid+"/ctl", sys->OWRITE);
	#sys->write(fd, array of byte "killgrp", len "killgrp");
}

mux(infd: ref Sys->FD, exportfd: ref Sys->FD, mountfd: ref Sys->FD, ctl: chan of int)
{
	buf := array[Styx->MAXRPC] of byte;
	
	ctl <-= sys->pctl(0,nil);
	
	# mux the inbound connection to the two pipes 
	while(1) {
		count := sys->readn(infd, buf, 5);
		if(count <= 0) {
			ctl <-= count;
			return;
		}			
		if(count < 5) {
			sys->fprint(sys->fildes(2), "readn returned: %d\n", count);
			raise "short read of packet";
		}
		
		size := (int buf[1] << 8) | int buf[0];
		size |= ((int buf[3] << 8) | int buf[2]) << 16;
		
		if(size > Styx->MAXRPC)
			raise "oversized packet";	
		
		op := int buf[4];
		if(op == 0) {	# other side closed mount
			exportfd = nil;
			ctl <-= 1;
			continue;
		}
		
		count = sys->readn(infd, buf[5:], size-5);
		if(count <= 0) {
			sys->fprint(sys->fildes(2), "readn infd returned: %d\n", count);
			ctl <-= count;
			return;
		}		
		if(count < size-5) {
 			raise "short read of packet";
		}
		
		whichfd := exportfd;
		if(op % 2) 
			whichfd = mountfd;
		
		count = sys->write(whichfd, buf, size);
		
		if(count < size) {
			sys->fprint(sys->fildes(2), "write returned %d\n", count);
			raise "short write of packet";
		}
	}	
}

# kill a thread
whack(pid: int) 
{
	msg := "kill";
	pidstr := string pid;
	fd := sys->open("/prog/"+pidstr+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->write(fd, array of byte msg, len msg);
}

uplink(infd: ref sys->FD, outfd: ref sys->FD, out: string, in: string)
{
	muxpid, exportpid, mountpid: int;
	muxctl := chan of int;
	exportctl := chan of int;
	mountctl := chan of int;
	status := 0;
	# lay pipe
	inpipe := array[2] of ref sys->FD;
	outpipe := array[2] of ref sys->FD;
	
	if(sys == nil)
		sys = load Sys Sys->PATH;
	
	if( sys->pipe(inpipe) < 0 ) raise "Couldn't allocate pipe";
	if( sys->pipe(outpipe) < 0 ) raise "Couldn't allocate pipe";
	
	# splice output of pipes back to file descriptor
	spawn splice(inpipe[1], outfd, mountctl);
	spawn splice(outpipe[1], outfd, exportctl);
	exportpid =<- exportctl;
	mountpid =<- mountctl;
	outfd = nil;
	
	if ( sys->export(outpipe[0], out, Sys->EXPASYNC) < 0 ) 
		raise "problem with export";	
	
	spawn mountit(inpipe[0], in);
	
	inpipe[0] = nil;
	outpipe[0] = nil;
	
	spawn mux(infd, outpipe[1], inpipe[1], muxctl);
	muxpid =<- muxctl;
	
	while(1) {
		alt {
			status = <- muxctl =>
				if(status <= 0) {
					muxpid = 0;
					whack(mountpid);
					whack(exportpid);
					return;
				}
				if(status == 1) {
					# cleanup export
					whack(exportpid);
					exportpid = 0;
				}
			
			status = <- mountctl => # we closed our end of the mount
				mountpid = 0;
				msg := array[5] of {* => byte 0};
				msg[0] = byte 5;
				sys->write(infd, msg, 5);	# notify other end
				if(exportpid == 0) {
					whack(muxpid);
					return;
				}
				
			status = <- exportctl =>
				exportpid = 0;
				if(mountpid == 0) {
					whack(muxpid);
					return;
				}
		};
	}
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	
	if(len argv < 3) {
		sys->fprint(sys->fildes(2), "usage: duct <export-path> <mount-point>\n");
		return;
	}
	
	out := hd tl argv;
	in := hd tl tl argv;
	
	spawn uplink(sys->fildes(0), sys->fildes(1), out, in);
}