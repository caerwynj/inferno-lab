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

Nil: ref Sexp;
T: ref Sexp;
Env: ref Sexp;
Procedure: ref Sexp;
Labeled: ref Sexp;
Unbound: ref Sexp;
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
	ctxt.addbuiltin("FullForm", myself);
	Nil = ref Sexp.String("nil", nil);
	T = ref Sexp.String("t", nil);
	Procedure = ref Sexp.String("&procedure", "");
	Labeled = ref Sexp.String("&labeled", "");
	Unbound = ref Sexp.String("&unbound", "");
	Env = ref Sexp.List(nil);
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
	"FullForm" =>
		return builtin_fullform(ctxt, argv, last);
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


stack: list of list of ref Sexp;

push(s:string)
{
		l := hd stack;
		stack = tl stack;
		l = ref Sexp.String(s, "") :: l;
		stack = l :: stack;
}

pushlist()
{
		nlist : list of ref Sexp;
		nlist = nil;
		stack = nlist :: stack;
}

poplist()
{
		nlist := hd stack;
		stack = tl stack;
		l := hd stack;
		stack = tl stack;
		l = ref Sexp.List(reverse(nlist)) :: l;
		stack = l :: stack;

}
typname:= array[] of {"Block", "Var", "quote", "SquashQuote", "Redir", 
	"Dup", "List", "Seq", "Concat", "Pipe", "Adj", "Word",
	"Nowait", "Squash", "Count", "Set", "SetLocal"};

n2s(n: ref Node): ref Sexp
{
	stack = nil;
	nlist : list of ref Sexp;
	nlist = nil;
	stack = nlist :: stack;
	transform(n);
	nlist = hd stack;
	if(nlist != nil && (hd nlist) != nil)
		return (hd nlist);
	return nil;
}

transform(n: ref Node)
{
	if(n == nil)
		return;
#	fprint(stderr, "dbg: %s\n", typs[n.ntype]);
#	if(n.ntype == n_WORD)
#		fprint(stderr, "\t%s\n",  n.word);
	case n.ntype {
	n_BLOCK => 
		pushlist();
		transform(n.left);
		poplist();
	n_ADJ or n_SEQ=>
		transform(n.left);
		transform(n.right);
	n_WORD =>
		push(n.word);
	n_VAR =>
		pushlist();
		push(typname[n.ntype]);
		transform(n.left);
		if (n.right != nil)
			transform(n.right);
		poplist();
	n_SQUASH or n_COUNT or n_BQ or n_BQ2 or n_LIST or n_NOWAIT =>	
		pushlist();
		push(typname[n.ntype]);
		transform(n.left);
		poplist();
	n_CONCAT =>
		pushlist();
		push("Concat");
		transform(n.left);
		transform(n.right);
		poplist();
	n_ASSIGN =>
		push("Assign");
		transform(n.left);
		transform(n.right);
	n_LOCAL =>
		push("LocalAssign");
		transform(n.left);
		transform(n.right);
	* =>
		pushlist();
		push(typname[n.ntype]);
		transform(n.left);
		transform(n.right);
		poplist();
	}
}


builtin_eval(nil: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n: ref Node;
	s := "";
	if(argv == nil)
		return "arg error";
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
#	se := n2s(n);
	se := eval(n2s(n), Env);
	if(se != nil)
		s = se.text() + "\n";
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

builtin_fullform(nil: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n: ref Node;
	s := "";
	if(argv == nil)
		return "arg error";
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
	se := n2s(n);
	if(se != nil)
		s = se.text() + "\n";
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

numberp(e: ref Sexp): int
{
	if(e == nil)
		return 0;
	pick s := e {
	String =>
		for(i:=0; i<len s.s; i++)
			if(!isdigit(s.s[i]))
				return 0;
		return 1;
	* =>
		return 0;
	}
}

atom(e: ref Sexp): int
{
	if(e == nil)
		return 0;
	pick s := e {
	String =>
		return 1;
	List =>
		if(s.l == nil)
			return 1;
		else
			return 0;
	* =>
		return 0;
	}
}

car(e: ref Sexp): ref Sexp
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		if(s.l == nil)
			return ref Sexp.List(nil);
		else 
			return hd s.l;
	* =>
		return nil;
	}
}

cdr(e: ref Sexp): ref Sexp
{
	if(e == nil)
		return nil;
	pick s := e {
	List =>
		if(s.l == nil)
			return ref Sexp.List(nil);
		else 
			return ref Sexp.List(tl s.l);
	* =>
		return nil;
	}
}

caadr(e: ref Sexp): ref Sexp {return car(car(cdr(e)));}
caar(e: ref Sexp): ref Sexp {return car(car(e));}
cadar(e: ref Sexp): ref Sexp {return car(cdr(car(e)));}
caddar(e: ref Sexp): ref Sexp {return car(cdr(cdr(car(e))));}
cadddr(e: ref Sexp): ref Sexp {return car(cdr(cdr(cdr(e))));}
caddr(e: ref Sexp): ref Sexp {return car(cdr(cdr(e)));}
cadr(e: ref Sexp): ref Sexp {return car(cdr(e));}
cdadr(e: ref Sexp): ref Sexp {return cdr(car(cdr(e)));}
cdar(e: ref Sexp): ref Sexp {return cdr(car(e));}

eq(e: ref Sexp, f: ref Sexp): int
{
	if(e == nil || f == nil)
		return 0;
	if(null(e) && null(f))
		return 1;
	pick s := e {
	String =>
		pick r := f {
		String =>
			return s.s == r.s;
		* =>
			return 0;
		}
	* =>
		return 0;
	}
}

null(e: ref Sexp): int
{
	if(e == nil)
		return 0;
	pick s:=e {
	List =>
		if(s.l == nil)
			return 1;
	}
	return 0;
}

cons(e: ref Sexp, f: ref Sexp): ref Sexp
{
	if(e == nil || f == nil)
		return nil;
	pick s := f {
	List =>
		return ref Sexp.List(e :: s.l);
	}
	return nil;
}

value(name, env: ref Sexp): ref Sexp
{
#	fprint(stderr, "value %s in %s\n", name.text(), env.text());
	return value1(name, lookup(name, env));
}

value1(nil, slot: ref Sexp): ref Sexp
{
	if(eq(slot, Unbound)) {
		return error("value1 unbound");
	} else
		return car(slot);
#		return slot;
}

error(s: string): ref Sexp
{
	fprint(stderr, "error at %s\n", s);
	return nil;
}

lookup(name, env: ref Sexp): ref Sexp
{
	if(null(env))
		return Unbound;
	else
		return lookup1(name, caar(env), cdar(env), env);
}

lookup1(name, vars, vals, env: ref Sexp): ref Sexp
{
#	fprint(stderr, "lookup1 name %s, vars %s, vals %s\n", name.text(), vars.text(), vals.text());
	if(null(vars))
		return lookup(name, cdr(env));
	else if(eq(name, car(vars))){
		if(atom(car(vals)))
			return vals;
		else if(eq(caar(vals), Labeled))
			return ref Sexp.List(ref Sexp.List(Procedure :: cadar(vals) :: caddar(vals) :: env :: nil) :: nil);
		else
			return vals;
	} else
		return lookup1(name, cdr(vars), cdr(vals), env);
}

evcon(n, env: ref Sexp): ref Sexp
{
	if(null(n))
		return error("evcon");
	if(eq(eval(caar(n), env), T))
		return eval(cadar(n), env);
	else
		return evcon(cdr(n), env);
}

evlis(n, env: ref Sexp): ref Sexp
{
	if(n == nil || null(n))
		return ref Sexp.List(nil);
	else
		return cons(eval(car(n), env), evlis(cdr(n), env));
}

bind(vars, args, env: ref Sexp): ref Sexp
{
	return cons(cons(vars, args), env);
}

apply(fun, args: ref Sexp): ref Sexp
{
#	fprint(stderr, "apply %s to %s\n", fun.text(), args.text());
	if(eq(car(fun), Procedure))
		return eval(caddr(fun), bind(cadr(fun), args, cadddr(fun)));
	else
		return error("apply");
}

eval(n, env: ref Sexp): ref Sexp
{
#	fprint(stderr, "eval %s in %s\n", n.text(), env.text());
	if(n == nil)
		return nil;
	else if(atom(n)){
		if(eq(n, Nil))
			return n;
		else if(eq(n, T))
			return n;
		else if(numberp(n))
			return n;
		else
			return value(n, env);
	}else if(atom(car(n))){
		e := car(n);
		pick  s := e {
		String =>
		case s.s {
		"quote" =>
			return cadr(n);
		"atom" =>
			if(atom(eval(cadr(n), env)))
				return T;
			else
				return Nil;
		"eq" =>
			if(eq(eval(cadr(n), env), eval(caddr(n), env)))
				return T;
			else
				return Nil;
		"car" =>
			return car(eval(cadr(n), env));
		"cdr" =>
			return cdr(eval(cadr(n), env));
		"cons" =>
			return cons(eval(cadr(n), env), eval(caddr(n), env));
		"cond" =>
			return evcon(cdr(n), env);
		"lambda" =>
			return ref Sexp.List(Procedure :: cadr(n) :: caddr(n) :: env :: nil);
		"define" =>
			Env = ref Sexp.List(cons(cons(caadr(n), caar(env)),
				cons(ref Sexp.List(Labeled :: cdadr(n) :: caddr(n) :: nil), 
				cdar(env))) :: nil);
#			fprint(stderr, "new env %s\n", Env.text());
		* =>
			return apply(eval(car(n), env), evlis(cdr(n), env));
		}
		}
	}else{
		return apply(eval(car(n), env), evlis(cdr(n), env));
	}
	return nil;
}
