implement Xymodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "xylib.m";
	xylib: Xylib;
	Value, Option: import xylib;

types(): string
{
	return "fs";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
}

run(r: chan of ref Value, nil: list of Option, args: list of ref Value)
{
	if((reply := <-r) != nil){
		addr := (hd args).gets();
		(ok, c) := sys->dial(addr, nil);
		if(ok == -1){
			sys->fprint(sys->fildes(2), "dial: cannot dial %q: %r", addr);
			reply.send(nil);
		}
		reply.send(ref Value.F(c.dfd));
	}
}
