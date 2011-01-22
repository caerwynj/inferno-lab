implement Reducer;

include "sys.m";
include "bufio.m";
include "mapred.m";

reduce(nil: string, v: chan of string, emit: chan of string)
{
	value := 0;
	while((s :=<- v) != nil)
		value += int s;
	emit <-= string value;
}
