implement Btreefetch;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "btree.m";
	btreem: Btreem;
	Btree: import btreem;

Btreefetch : module {
	init: fn(nil:ref Draw->Context, args: list of string);
};

init(nil:ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	btreem = load Btreem Btreem->PATH;
	
	btreem->init();	
	
	args = tl args;
	index := "index.bt";
	if(len args > 0){
		index = hd args;
		args = tl args;
	}
	bt := Btree.open(index, Sys->ORDWR);
	if(args == nil){
		err := 0;
		f := bufio->fopen(sys->fildes(0), Bufio->OREAD);
		while((s := f.gets('\n')) != nil){
			s = s[0:len s-1];
			val := bt.fetch(array of byte s);
			sys->print("%s %s\n", s, string val);
		}
		if(err)
			raise "fail:store";
	}else if(len args == 1){
		val := bt.fetch(array of byte hd args);
		sys->print("%s %s\n", hd args, string val);
	}else{
		sys->fprint(sys->fildes(2), "usage: fetch index.bt key\n");
		exit;
	}
}
