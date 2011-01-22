implement Command;
include "sys.m";
include "draw.m";
include "bufio.m";
include "sexprs.m";
	sexp: Sexprs;
	Sexp: import sexp;


include "sh.m";

init(nil: ref Draw->Context, nil: list of string)
{
	sys := load Sys Sys->PATH;
	sexp = load Sexprs Sexprs->PATH;
	sexp->init();
	
	e := ref Sexp.String("test", "");
	s := ref Sexp.List(nil);
	r : ref Sexp;
#	*s = *e;
#toy0.b:21: type clash in '*s' of type Sexp.List = '*e' of type Sexp.String

	r = s;
#	pick rr := r {
#	List =>
#		sys->print("is a list\n");
#	String =>
#		sys->print("is a string\n");
#	}
	*r = *e;
	sys->print("%s\n", s.text());
#	pick rr := r {
#	List =>
#		sys->print("is a list\n");
#	String =>
#		sys->print("is a string\n");
#	}
#	*e = *s;
#	sys->print("%s\n", e.text());

}

