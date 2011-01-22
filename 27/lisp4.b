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
	n_ADJ =>
		transform(n.left);
		transform(n.right);
	n_SEQ =>
		push("Seq");
		pushlist();
		transform(n.left);
		poplist();
		pushlist();
		transform(n.right);
		poplist();
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


builtin_eval(c: ref Context, argv: list of ref Listnode, nil: int): string
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
	se := eval(n2s(n), c);
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
			return nil;
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
			return nil;
		else 
			return ref Sexp.List(tl s.l);
	* =>
		return nil;
	}
}

eq(e: ref Sexp, f: ref Sexp): int
{
	if(e == nil || f == nil)
		return 0;
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
		s.l = e :: s.l;
		return s;
	}
	return nil;
}

value(e: ref Sexp, env: ref Context): ref Sexp
{
	if(e == nil)
		return nil;
	pick s := e {
	String =>
		l := env.get(s.s);
		if(l == nil)
			return nil;
		ln := hd l;
		if(ln.cmd == nil)
			return ref Sexp.String(ln.word, nil);
		else
			return n2s(ln.cmd);
	}
	return nil;
}

evcon(n: ref Sexp, env: ref Context): ref Sexp
{
	nn := eval(car(car(n)), env);
	if(eq(nn, T))
		return eval(car(cdr(car(n))), env);
	else
		return evcon(cdr(n), env);
}

evlis(n: ref Sexp, env: ref Context): list of ref Sexp
{
	if(n == nil || null(n))
		return nil;
	else
		return eval(car(n), env) :: evlis(cdr(n), env);
}

bind(n: ref Sexp, args: list of ref Sexp, nil: ref Context)
{
#	fprint(stderr, "bind %s to %s\n", cmd2string(n), cmd2string(hd args));
	if(n == nil || args == nil)
		return;
}

apply(n: ref Sexp, args: list of ref Sexp, env: ref Context): ref Sexp
{
	env.push();
	bind(car(n), args, env);
	nn := eval(car(cdr(n)), env);
	env.pop();
	return nn;
}

eval(n: ref Sexp, env: ref Context): ref Sexp
{
	if(n == nil)
		return nil;
	else if(atom(n)){
		if(eq(n, Nil))
			return n;
		else if(eq(n, T))
			return n;
		else
			return value(n, env);
	}else if(atom(car(n))){
		e := car(n);
		pick  s := e {
		String =>
		case s.s {
		"quote" =>
			return car(cdr(n));
		"atom" =>
			if(atom(eval(car(cdr(n)), env)))
				return T;
			else
				return Nil;
		"eq" =>
			if(eq(eval(car(cdr(n)), env), eval(car(cdr(cdr(n))), env)))
				return T;
			else
				return Nil;
		"car" =>
			return car(eval(car(cdr(n)), env));
		"cdr" =>
			return cdr(eval(car(cdr(n)), env));
		"cons" =>
			return cons(eval(car(cdr(n)), env), eval(car(cdr(cdr(n))), env));
		"cond" =>
			return evcon(cdr(n), env);
		* =>
			return apply(value(car(n), env), reverse(evlis(cdr(n), env)), env);
		}
		}
	}else{
		nn := cdr(n);
		return nn;
	}
	return nil;
}
