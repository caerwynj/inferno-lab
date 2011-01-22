implement Btreetest;

include "sys.m";
	sys: Sys;

include "draw.m";

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include "btree.m";
	btreem: Btreem;
	Btree: import btreem;

Btreetest : module {
	init: fn(nil:ref Draw->Context, nil: list of string);
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
			key: string;
			for(i :=0; i < len s; i++)
				if(s[i] == ' ' || s[i] == '\t'){
					key = s[0:i];
					s = s[i+1:];
					break;
				}
			if(key == nil){
				sys->fprint(sys->fildes(2), "dbm/store: bad input\n");
				raise "fail:error";
			}
			bt.store(array of byte key, array of byte s);
		}
		if(err)
			raise "fail:store";
	}else if(len args == 2){
		bt.store(array of byte hd args , array of byte hd tl args);
	}else{
		sys->fprint(sys->fildes(2), "usage: store key val\n");
		exit;
	}
	bt.flush();
	bt.close();
}
