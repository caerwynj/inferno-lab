implement Xymodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "xylib.m";
	xylib: Xylib;
	Value, Option: import xylib;

types(): string
{
	return "sfs-a-b-c-xs";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
}

After, Before, Create: con 1<<iota;

run(r: chan of ref Value, opts: list of Option, args: list of ref Value)
{
	if((reply := <-r) != nil){
		flag := Sys->MREPL;
		aname := "";
		for(; opts != nil; opts = tl opts){
			case (hd opts).opt {
			'a' =>
				flag = After & (flag&Sys->MCREATE);
			'b' =>
				flag = Before & (flag&Sys->MCREATE);
			'c' =>
				flag |= Create;
			'x' =>
				aname = (hd (hd opts).args).gets();
			}
		}
		fd := (hd args).getfd();
		dir := (hd tl args).gets();
		if(sys->mount(fd, nil, dir, flag, aname) == -1)
			sys->fprint(sys->fildes(2), "mount error on %#q: %r", dir);
		reply.send(ref Value.S("ok"));
	}
}
