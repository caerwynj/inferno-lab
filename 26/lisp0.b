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

atom(n: ref Node): int
{
	if(n == nil)
		return 0;
	else if(n.ntype == n_WORD)
		return 1;
	else if(n.ntype == n_BLOCK && n.left == nil)
		return 1;
	else
		return 0;
}

car(n: ref Node): ref Node
{
	if(n == nil || n.ntype != n_BLOCK)
		return nil;
	n = n.left;
	for (l := n; l != nil; l = l.left){
		if(l.ntype == n_BLOCK || l.ntype == n_WORD || l.ntype == n_BQ){
			return l;
		}
	}
	return nil;
}

cdr(n: ref Node): ref Node
{
	if(n == nil || n.ntype != n_BLOCK)
		return nil;
	tog=0;
	return mk(n_BLOCK, cdr_(n.left), nil);
}

tog: int;
cdr_(n: ref Node): ref Node
{
	if (n == nil)
		return nil;
	nn: ref Node = nil;
#	fprint(stderr, "dbg: %s\n", typs[n.ntype]);
	if(n.ntype == n_BLOCK || n.ntype == n_WORD || n.ntype == n_BQ){
		if(tog && (n.ntype == n_BLOCK || n.ntype == n_BQ))
			nn = mk(n.ntype, cdr_(n.left), nil);
		else if(tog && n.ntype == n_WORD)
			nn = n;
		else
			tog = 1;
	}else if(n.ntype == n_ADJ || n.ntype == n_SEQ){
		left := cdr_(n.left);
		right := cdr_(n.right);
		if(left == nil)
			nn = right;
		else
			nn = mk(n.ntype, left, right);
	}else{
		nn = mk(n.ntype, cdr_(n.left), cdr_(n.right));
	}
	return nn;
}

numberp(n: ref Node): int
{
	if(n == nil || n.ntype != n_WORD)
		return 0;
	for(i:=0; i<len n.word; i++)
		if(!isdigit(n.word[i]))
			return 0;
	return 1;
}

eq(n: ref Node, s: ref Node): int
{
	if(n == nil || n.ntype != n_WORD || s == nil || s.ntype != n_WORD)
		return 0;
	return n.word == s.word;
}

null(n: ref Node): int
{
	if(n == nil || n.ntype != n_BLOCK)
		return 0;
	if(n.left != nil)
		return 0;
	return 1;
}

cons(x: ref Node, y: ref Node): ref Node
{
	if(x == nil || y == nil || y.ntype != n_BLOCK)
		return nil;
	tog = 0;
	if(y.left == nil)
		return mk(n_BLOCK, x, nil);
	else
		return mk(n_BLOCK, cons_(x, y.left), nil);
}

cons_(x: ref Node, n: ref Node): ref Node
{
	if (n == nil)
		return nil;
	nn: ref Node = nil;
	if(n.ntype == n_BLOCK || n.ntype == n_WORD){
		if(tog && n.ntype == n_BLOCK)
			nn = mk(n_BLOCK, cons_(x, n.left), nil);
		else if(tog && n.ntype == n_WORD)
			nn = n;
		else{
			tog = 1;
			nn = mk(n_ADJ, x, cons_(x, n));
		}
	}else{
		nn = mk(n.ntype, cons_(x, n.left), cons_(x, n.right));
	}
	return nn;
}

value(n: ref Node, env: ref Context): ref Node
{
	if(n == nil)
		return nil;
	l := env.get(n.word);
	if(l == nil)
		return nil;
	ln := hd l;
	if(ln.cmd == nil)
		return ref Node(n_WORD, nil, nil, ln.word, nil);
	else
		return ln.cmd;
}

evcon(n: ref Node, env: ref Context): ref Node
{
	nn := eval(car(car(n)), env);
	if(eq(nn, T))
		return eval(car(cdr(car(n))), env);
	else
		return evcon(cdr(n), env);
}

evlis(n: ref Node, env: ref Context): list of ref Node
{
	if(n == nil || null(n))
		return nil;
	else
		return eval(car(n), env) :: evlis(cdr(n), env);
}

depth:=0;
bind(n: ref Node, args: list of ref Node, env: ref Context)
{
#	fprint(stderr, "bind %s to %s\n", cmd2string(n), cmd2string(hd args));
	if(n == nil || args == nil)
		return;
#	if(depth++>100){
#		fprint(stderr, "depth exceeded\n");
#		return;
#	}
	else if(n.ntype == n_ADJ) {
		bind(n.right, args, env);
		bind(n.left, tl args, env);
	}else if(n.ntype == n_WORD){
#		fprint(stderr, "set %s=%s\n", n.word , cmd2string(hd args));
		env.setlocal(n.word, ref Listnode((hd args), nil) :: nil);
	}else 
		bind(n.left, args, env);
}

apply(n: ref Node, args: list of ref Node, env: ref Context): ref Node
{
	env.push();
	bind(car(n), args, env);
	nn := eval(car(cdr(n)), env);
	env.pop();
	return nn;
}

eval(n: ref Node, env: ref Context): ref Node
{
	if(n == nil)
		return nil;
	else if(n.ntype == n_BQ)
		return n.left;
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
		s := car(n);
		case s.word {
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
	}else{
		nn := cdr(n);
		return nn;
	}
	return nil;
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
	n = eval(n, c);
	s = cmd2string(n) + "\n";
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


cmd2string(n: ref Node): string
{
	if (n == nil)
		return "";

#	sys->fprint(sys->fildes(2), "dbg: %s\n", typs[n.ntype]);
	s: string;
	case n.ntype {
	n_BLOCK =>	s = "{" + cmd2string(n.left) + "}";
	n_VAR =>		s = "$" + cmd2string(n.left);
				if (n.right != nil)
					s += "(" + cmd2string(n.right) + ")";
	n_SQUASH =>	s = "$\"" + cmd2string(n.left);
	n_COUNT =>	s = "$#" + cmd2string(n.left);
	n_BQ =>		s = "`" + cmd2string(n.left);
	n_BQ2 =>		s = "\"" + cmd2string(n.left);
	n_LIST =>		s = "(" + cmd2string(n.left) + ")";
	n_SEQ =>		s = cmd2string(n.left) + " " + cmd2string(n.right);
	n_NOWAIT =>	s = cmd2string(n.left) + "&";
	n_CONCAT =>	s = cmd2string(n.left) + "^" + cmd2string(n.right);
	n_ASSIGN =>	s = cmd2string(n.left) + "=" + cmd2string(n.right);
	n_LOCAL =>	s = cmd2string(n.left) + ":=" + cmd2string(n.right);
	n_ADJ =>		s = cmd2string(n.left) + " " + cmd2string(n.right);
	n_WORD =>	s = quote(n.word, 1);
	* =>			s = sys->sprint("unknown%d", n.ntype);
	}
	return s;
}

# convert s into a suitable format for reparsing.
# if glob is true, then GLOB chars are significant.
# XXX it might be faster in the more usual cases 
# to run through the string first and only build up
# a new string once we've discovered it's necessary.
quote(s: string, glob: int): string
{
	needquote := 0;
	t := "";
	for (i := 0; i < len s; i++) {
		case s[i] {
		'{' or '}' or '(' or ')' or '`' or '&' or ';' or '=' or '>' or '<' or '#' or
		'|' or '*' or '[' or '?' or '$' or '^' or ' ' or '\t' or '\n' or '\r' =>
			needquote = 1;
		'\'' =>
			t[len t] = '\'';
			needquote = 1;
		GLOB =>
			if (glob) {
				if (i < len s - 1)
					i++;
			}
		}
		t[len t] = s[i];
	}
	if (needquote || t == nil)
		t = "'" + t + "'";
	return t;
}

quoted(val: list of ref Listnode, quoteblocks: int): string
{
	s := "";
	for (; val != nil; val = tl val) {
		el := hd val;
		if (el.cmd == nil || (quoteblocks && el.word != nil))
			s += quote(el.word, 0);
		else {
			cmd := cmd2string(el.cmd);
			if (quoteblocks)
				cmd = quote(cmd, 0);
			s += cmd;
		}
		if (tl val != nil)
			s[len s] = ' ';
	}
	return s;
}

mk(ntype: int, left, right: ref Node): ref Node
{
	return ref Node(ntype, left, right, nil, nil);
}

reverse[T](l: list of T): list of T
{
	t: list of T;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}
