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
	return "oo";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
}

run(r: chan of ref Value, nil: list of Option, args: list of ref Value)
{
	if((replyc :=<-r) != nil)
		replyc.send(hd args);
}
