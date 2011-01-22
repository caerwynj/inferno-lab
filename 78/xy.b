implement Xy;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "readdir.m";
include "xylib.m";
	xylib: Xylib;
	Value, type2s: import xylib;
	
Xy: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

badmod(path: string)
{
	sys->fprint(stderr(), "xy: cannot load %s: %r\n", path);
	raise "fail:bad module";
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
	if(xylib == nil)
		badmod(Xylib->PATH);
	xylib->init();
	argv = tl argv;

	if(argv == nil)
		usage();
	s := hd argv;
	if(tl argv == nil && s != nil && s[0] == '{' && s[len s - 1] == '}')
		s = "void " + hd argv;
	else {
		s = "void {" + hd argv;
		for(argv = tl argv; argv != nil; argv = tl argv){
			a := hd argv;
			if(a == nil || a[0] != '{')		# }
				s += sys->sprint(" %q", a);
			else
				s += " " + hd argv;
		}
		s += "}";
	}
	m := load Xymodule "/dis/xy/eval.dis";
	if(m == nil)
		badmod("eval.dis");
	if(!xylib->typecompat("as", m->types())){
		sys->fprint(stderr(), "fs: eval module implements incompatible type (usage: %s)\n",
				xylib->cmdusage("eval", m->types()));
		raise "fail:bad eval module";
	}
	m->init();
	r := chan of ref Value;
	spawn m->run(r, nil, ref Value.S(s) :: nil);
	rv := ref Value.O(r);
	v:= rv.gets();
	fail: string;
	if(v == nil)
		fail = "error";
	if(fail != nil)
		raise "fail:" +fail;
}

usage()
{
	fd := stderr();
	sys->fprint(fd, "usage: fs expression\n");
	sys->fprint(fd, "verbs are:\n");
	if((readdir := load Readdir Readdir->PATH) == nil){
		sys->fprint(fd, "fs: cannot load %s: %r\n", Readdir->PATH);
	}else{
		(a, nil) := readdir->init("/dis/xy", Readdir->NAME|Readdir->COMPACT);
		for(i := 0; i < len a; i++){
			f := a[i].name;
			if(len f < 4 || f[len f - 4:] != ".dis")
				continue;
			m := load Xymodule "/dis/xy/" + f;
			if(m == nil)
				sys->fprint(fd, "\t(%s: cannot load: %r)\n", f[0:len f - 4]);
			else
				sys->fprint(fd, "\t%s\n", xylib->cmdusage(f[0:len f - 4], m->types()));
		}
	}
	raise "fail:usage";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
