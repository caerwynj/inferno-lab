implement Mapper;

include "sys.m";
include "mapred.m";
include "regex.m";

# the map function may not get the whole file in one go. maybe
# just a segment, or a line.
pattern := "asdf";

map(key, value: string, emit: chan of (string, string))
{
	regex := load Regex Regex->PATH;
	Re: import regex;
	(re, nil) := regex->compile(pattern,0);
	if(regex->executese(re, value, (0, len value-1), 1, 1) != nil)
		emit <-= (key, value);
}
