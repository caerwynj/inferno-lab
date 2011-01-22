implement Command;

include "sh.m";
include "sys.m";
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;


init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	io := bufio->fopen(sys->fildes(0), Sys->OREAD);
	last := "";
	cnt := 0;
	while((s := io.gets('\n')) != nil){
		(n, f) := sys->tokenize(s, " \t\n\r");
		if(n != 2)
			continue;
		if(hd f == last)
			cnt += int hd tl f;
		else{
			if(last != "")
				sys->print("%s %d\n", last, cnt);
			last = hd f;
			cnt = int hd tl f;
		}
	}
	if(last != "")
		sys->print("%s %d\n", last, cnt);
}
