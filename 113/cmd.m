
include "sys.m";
sys: Sys;
print: import sys;

include "draw.m";

Command: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	main(argv);
}
