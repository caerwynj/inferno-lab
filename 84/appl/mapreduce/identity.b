implement Reducer;

include "sys.m";
include "bufio.m";
include "mapred.m";

reduce(nil: string, v: chan of string, emit: chan of string)
{
	while((s :=<- v) != nil)
		emit <-= string s;
}
