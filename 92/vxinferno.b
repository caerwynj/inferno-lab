implement Vxinferno;

include "sys.m";
include "draw.m";
include "vxrun.m";

Vxinferno:module{
	init:fn(ctxt:ref Draw->Context, args:list of string);
};

init(nil:ref Draw->Context, args:list of string)
{
	sys := load Sys Sys->PATH;
	vxrun := load Vxrun Vxrun->PATH;
	if(vxrun == nil){
		raise "fail to load";
	}
	n := vxrun->run(tl args);
	sys->print("retval %d\n", n);
}
