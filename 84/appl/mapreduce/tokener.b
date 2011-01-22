implement Mapper;

include "sys.m";
	sys: Sys;
include "mapred.m";
include "string.m";
	str: String;

# the map function may not get the whole file in one go. maybe
# just a segment, or a line.

map(key, value: string, emit: chan of (string, string))
{
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(str == nil)
		str = load String String->PATH;
	(nil, f) := sys->tokenize(value, "[]{}()!@#$%^&*?><\":;.,|\\-_~`'+=/ \t\n\r");
	for ( ; f != nil; f = tl f) {
		ss := str->tolower(hd f);
		emit <-= (key, ss);
	}
}
