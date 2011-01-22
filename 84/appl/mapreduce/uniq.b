implement Reducer;

include "sys.m";
include "bufio.m";
include "mapred.m";

reduce(nil: string, v: chan of string, emit: chan of string)
{
	s, last : string;
	last = <- v;
	if(last == nil)
		return;
	while((s =<- v) != nil){
		if(s != last){
			emit <-= last;
			last = s;
		}
	}
	emit <-= last;
}
