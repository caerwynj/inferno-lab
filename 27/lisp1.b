implement Shellbuiltin;

include "sys.m";
	sys: Sys;
	fprint, fildes: import sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;
	n_BLOCK,  n_VAR, n_BQ, n_BQ2, n_REDIR,
	n_DUP, n_LIST, n_SEQ, n_CONCAT, n_PIPE, n_ADJ,
	n_WORD, n_NOWAIT, n_SQUASH, n_COUNT,
	n_ASSIGN, n_LOCAL, Node, GLOB : import sh;

include "bufio.m";
include "sexprs.m";
	sexpr: Sexprs;
	Sexp: import sexpr;

include "libc.m";
	libc: Libc;
	isdigit: import libc;

Nil: ref Node;
T: ref Node;
stderr: ref Sys->FD;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	libc = load Libc Libc->PATH;
	sexpr = load Sexprs Sexprs->PATH;
	sexpr->init();
	sh = shmod;
	myself = load Shellbuiltin "$self";
	stderr = fildes(2);
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("echo: cannot load self: %r"));
	ctxt.addbuiltin("eval", myself);
	Nil = ref Node(n_WORD, nil,nil,"nil", nil);
	T = ref Node(n_WORD, nil,nil, "t", nil);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode, last: int): string
{
	case (hd argv).word {
	"eval" =>
		return builtin_eval(ctxt, argv, last);
	}
	return nil;
}

runsbuiltin(nil: ref Sh->Context, nil: Sh,
			nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

argusage(ctxt: ref Context)
{
	ctxt.fail("usage", "usage: arg [opts {command}]... - args");
}

typs:= array[] of {"BLOCK", "VAR", "BQ", "BQ2", "REDIR", 
	"DUP", "LIST", "SEQ", "CONCAT", "PIPE", "ADJ", "WORD",
	"NOWAIT", "SQUASH", "COUNT", "ASSIGN", "LOCAL"};


islist(n: ref Node): int
{
	if(n == nil)
		return 0;
	return n.ntype == n_ADJ || n.ntype == n_SEQ;
}

transform(n: ref Node): ref Sexp
{
	if(n == nil)
		return nil;
#	fprint(stderr, "dbg: %s\n", typs[n.ntype]);
#	if(n.ntype == n_WORD)
#		fprint(stderr, "\t%s\n",  n.word);
	case n.ntype {
	n_BLOCK => 
			lists := transform(n.left);
			pick s := lists{
			List =>
				if(islist(n.left)){
					return ref Sexp.List(reverse(s.l));
				}else{
					return ref Sexp.List(s :: nil);
				}
			* =>
				return ref Sexp.List(lists :: nil);
			}
	n_ADJ or n_SEQ =>
		ll := transform(n.left);
		rr := transform(n.right);
		if(islist(n.left) && islist(n.right)){
			pick sl := ll {
			List =>
				pick sr := rr {
				List =>
					nl: list of ref Sexp;
					nl = reverse(sr.l);
					for(; nl != nil; nl = tl nl);
						sl.l = hd nl :: sl.l;
					return sl;
				}
			}
		}else if(islist(n.left)){
			pick s := ll {
			List =>
				s.l = rr :: s.l;
				return s;
			* =>
				return nil;
			}
		}else if(islist(n.right)){
			pick s := rr {
			List =>
				nl: list of ref Sexp = nil;
				nl = reverse(s.l);
				nl = ll :: nl;
				s.l = reverse(nl);
				return s;
			* =>
				return nil;
			}
		}else
			return ref Sexp.List(rr :: ll :: nil);
	n_WORD =>	
		return ref Sexp.String(n.word, "");
	* => 
		return ref Sexp.String(n.word, "");
	}
	return nil;
}

builtin_eval(nil: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n: ref Node;
	ss: ref Sexp;
	s := "";
	if(argv == nil)
		return "arg error";
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
	ss = transform(n);
	s = ss.text() + "\n";
	{
		a := array of byte s;
		if (sys->write(sys->fildes(1), a, len a) != len a) {
			sys->fprint(sys->fildes(2), "echo: write error: %r\n");
			return "write error";
		}
		return nil;
	}exception{
		"write on closed pipe" =>
			sys->fprint(sys->fildes(2), "echo: write error: write on closed pipe\n");
			return "write error";
	}
}

reverse[T](l: list of T): list of T
{
	t: list of T;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}
