implement Next;

include "draw.m";
include "sys.m";

Next: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys := load Sys Sys->PATH;
	argv = tl argv;
	file := "next";
	if(argv != nil)
		file = hd argv;
	fd := sys->open(file, Sys->ORDWR);
	if(fd == nil){
		sys->fprint(sys->fildes(2), "next: open %r");
		exit;
	}
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0){
		sys->fprint(sys->fildes(2), "next: read %r");
		exit;
	}
	i := int string buf[:n];
	sys->print("%.4d\n", ++i);
	sys->seek(fd, big 0, 0);
	sys->fprint(fd, "%.4d", i);
}
