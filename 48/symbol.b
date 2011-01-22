implement Shellbuiltin;

# Take {1;2;3;4} {1;2}
# Drop {1;2;3;4} {3}
# Map, Apply, Length, Evaluate, Part
# List, Array, Range, Plus, Table, Fold, FoldList, Nest, NestList
# Prepend, Append, Insert, Delete, ReplacePart, Head, Rest
# Flatten, RotateLeft, RotateRight, Partition, Sequence
# Split, PadLeft, PadRight, Length, ListConvolve, Thread,
# Distribute, Inner, Outer, Rule, Reverse, Position, Depth, Level
# MapAt, MapAll, MapIndexed, MapThread, Scan, Function
# ComposeList


# "Mathematica is an infinite evaluation system"
# It keeps evaluating the expression until it no longer changes
# if you take the final result from an evaluation and use it as input
# you will get back the same result.

# Evaluation is under the control of the builtin
# it can just call evlis to turn a list of ref Listnode into an evaluated list of ref Listnode.

# for infinite streams we could create an IEval channel that does one iteration
# and outputs the string and stores it for the next iteration.

include "sys.m";
	sys: Sys;
	fprint, fildes: import sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context, cmd2string, stringlist2list, list2stringlist, parse: import sh;
	myself: Shellbuiltin;
	n_BLOCK,  n_VAR, n_BQ, n_BQ2, n_REDIR,
	n_DUP, n_LIST, n_SEQ, n_CONCAT, n_PIPE, n_ADJ,
	n_WORD, n_NOWAIT, n_SQUASH, n_COUNT,
	n_ASSIGN, n_LOCAL, Node, GLOB : import sh;

include "libc.m";
	libc: Libc;
	isdigit: import libc;

stderr: ref Sys->FD;

Rule: adt {
	lhs : list of ref Listnode;
	rhs : list of ref Listnode;
};

Definition: adt {
	name: string;
	rules: list of ref Rule;
};
defs: array of list of ref Definition;


initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	libc = load Libc Libc->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	stderr = fildes(2);
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("echo: cannot load self: %r"));
	ctxt.addbuiltin("Length", myself);
	ctxt.addbuiltin("Rest", myself);
	ctxt.addbuiltin("TreeView", myself);
	ctxt.addbuiltin("Part", myself);
	ctxt.addbuiltin("Apply", myself);
	ctxt.addbuiltin("FullForm", myself);
	ctxt.addbuiltin("Map", myself);
	ctxt.addbuiltin("Evaluate", myself);
	ctxt.addbuiltin("Range", myself);
	ctxt.addbuiltin("IEval", myself);
	ctxt.addbuiltin("Fold", myself);
	ctxt.addbuiltin("FoldList", myself);
	ctxt.addbuiltin("Nest", myself);
	ctxt.addbuiltin("NestList", myself);
	ctxt.addbuiltin("List", myself);
	ctxt.addbuiltin("Head", myself);

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
	"Length" =>
		return builtin_length(ctxt, argv, last);
	"Rest" =>
		return builtin_rest(ctxt, argv, last);
	"TreeView" =>
		return builtin_treeview(ctxt, argv, last);
	"Part" =>
		return builtin_part(ctxt, argv, last);
	"Apply" =>
		return builtin_apply(ctxt, argv, last);
	"FullForm" =>
		return builtin_fullform(ctxt, argv, last);
	"Map" =>
		return builtin_map(ctxt, argv, last);
	"Evaluate" =>
		return builtin_eval(ctxt, argv, last);
	"Range" =>
		return builtin_range(ctxt, argv, last);
	"IEval" =>
		return builtin_ieval(ctxt, argv, last);
	"Fold" =>
		return builtin_fold(ctxt, argv, last);
	"FoldList" =>
		return builtin_foldlist(ctxt, argv, last);
	"Nest" =>
		return builtin_nest(ctxt, argv, last);
	"NestList" =>
		return builtin_nestlist(ctxt, argv, last);
	"List" =>
		return builtin_list(ctxt, argv, last);
	"Head" =>
		return builtin_head(ctxt, argv, last);
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

builtinusage(ctxt: ref Context, s: string)
{
	ctxt.fail("usage", "usage: " + s);
}

builtin_head(nil: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 2)
		return puts("Head\n");
	args := tl val;
	if((hd args).cmd == nil)
		return puts((hd args).word);
	n := (hd args).cmd;
	for(;;) {
		if(n == nil)
			return puts("");
		if(n.ntype == n_SEQ)
			return puts("List\n");
		if(n.ntype == n_WORD)
			return puts(quote(n.word, 0) + "\n");
		n = n.left;
	}
}

builtin_list(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 2 || (hd tl val).word == nil)
		builtinusage(ctxt, "List a ...");
	args := tl val;
	n, nl: ref Node;
	for(i := args; i != nil; i = tl i){
		if((hd i).cmd == nil)
			n = ref Node(n_WORD, nil, nil, (hd i).word, nil);
		else
			n = (hd i).cmd;
		if(nl == nil)
			nl = n;
		else
			nl = mk(n_SEQ, nl, n);
	}
	return puts(cmd2string(mk(n_BLOCK, nl, nil)) + "\n");
}

builtin_fold(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 3 || (hd tl val).word == nil)
		builtinusage(ctxt, "Fold f arg list");
	f := (hd tl val).word;
	arg := ref Node(n_WORD, nil, nil, (hd tl tl val).word, nil);
	k :=tl tl tl val;
	n: ref Node;
	for(i := k; i != nil; i = tl i){
		n = ref Node(n_WORD, nil, nil, f, nil);
		n = mk(n_ADJ, n, arg);
		n = mk(n_ADJ, n,  ref Node(n_WORD, nil, nil, (hd i).word, nil));
		n = mk(n_BLOCK, n, nil);
		arg = n;
	}
	return puts(cmd2string(n) + "\n");
}

builtin_foldlist(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 3 || (hd tl val).word == nil)
		builtinusage(ctxt, "Fold f arg list");
	f := (hd tl val).word;
	arg := ref Node(n_WORD, nil, nil, (hd tl tl val).word, nil);
	k :=tl tl tl val;
	n: ref Node;
	nl: ref Node;
	for(i := k; i != nil; i = tl i){
		n = ref Node(n_WORD, nil, nil, f, nil);
		n = mk(n_ADJ, n, arg);
		n = mk(n_ADJ, n,  ref Node(n_WORD, nil, nil, (hd i).word, nil));
		n = mk(n_BLOCK, n, nil);
		arg = n;
		if(nl == nil)
			nl = n;
		else
			nl = mk(n_SEQ, nl, n);
	}
	return puts(cmd2string(mk(n_BLOCK, nl, nil)) + "\n");
}

builtin_nest(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 4 || (hd tl val).word == nil)
		builtinusage(ctxt, "Nest f arg num");
	f := (hd tl val).word;
	arg := ref Node(n_WORD, nil, nil, (hd tl tl val).word, nil);
	k := int (hd tl tl tl val).word;
	n: ref Node;
	for(i := 0; i<k; i++){
		n = ref Node(n_WORD, nil, nil, f, nil);
		n = mk(n_ADJ, n, arg);
		n = mk(n_BLOCK, n, nil);
		arg = n;
	}
	return puts(cmd2string(n) + "\n");
}

builtin_nestlist(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 4 || (hd tl val).word == nil)
		builtinusage(ctxt, "NestList f arg num");
	f := (hd tl val).word;
	arg := ref Node(n_WORD, nil, nil, (hd tl tl val).word, nil);
	k := int (hd tl tl tl val).word;
	n: ref Node;
	nl: ref Node;
	for(i := 0; i<k; i++){
		n = ref Node(n_WORD, nil, nil, f, nil);
		n = mk(n_ADJ, n, arg);
		n = mk(n_BLOCK, n, nil);
		arg = n;
		if(nl == nil)
			nl = n;
		else
			nl = mk(n_SEQ, nl, n);
	}
	return puts(cmd2string(mk(n_BLOCK, nl, nil)) + "\n");
}

builtin_range(ctxt: ref Context, val: list of ref Listnode, nil: int): string
{
	if (len val < 2 || (hd tl val).word == nil)
		builtinusage(ctxt, "range num");
	k := int (hd tl val).word;
	n := ref Node(n_WORD, nil, nil, "1", nil);
	for(i := 2; i<=k; i++)
		n = mk(n_SEQ, n, ref Node(n_WORD, nil, nil, string i, nil));
	return puts(cmd2string(mk(n_BLOCK,n,nil)) + "\n");
}

evlis(c: ref Context, argv: list of ref Listnode):list of ref Listnode
{
	nl : list of ref Listnode;
	for(l := argv; l != nil; l = tl l){
		if((hd l).cmd == nil){
			nl = hd l :: nl;
		}else{
			s := ieval(c, hd l :: nil);
			if(s != nil && s[0] == '{') {  #}
				(cmd, e) := parse(s);
				if(e == nil)
					nl = ref Listnode(cmd, nil) :: nl;
				else
					nl = ref Listnode(nil, s) :: nl;
			} else
				nl = ref Listnode(nil, s) :: nl;
		}
	}
	return reverse(nl);
}

MAXITER :con 100;
ieval(c: ref Context, argv: list of ref Listnode): string
{
	if((hd argv).cmd == nil)
		return nil;
	last := cmd2string((hd argv).cmd) + "\n";
	c.setoptions(Context.VERBOSE, 0);

	cnt := MAXITER;
	while(cnt-- > 0){
		s := eval(c, argv, 0);
		if (s == last)
			break;
		last = s;
		(cmd, e) := parse(s);
		if(e != nil)
			break;
		argv = ref Listnode(cmd, nil) :: nil;
	}
	c.setoptions(Context.VERBOSE, 1);
	return last;
}

builtin_ieval(c: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	s := "";
	c.setoptions(Context.VERBOSE, 0);
	if(argv == nil)
		return "arg error";
	s = ieval(c, argv);
	c.setoptions(Context.VERBOSE, 1);
	return puts(s);
}

eval(c: ref Context, argv: list of ref Listnode, nil: int): string
{
	(nlist, err) := bq(c, argv, nil); 
	if(err != nil)
		return cmd2string((hd argv).cmd) + "\n";

	return (hd nlist).word;
}

builtin_eval(c: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n: ref Node;
	s := "";
	c.setoptions(Context.VERBOSE, 0);
	if(argv == nil)
		return "arg error";
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
	s = eval(c, argv, 0);
	c.setoptions(Context.VERBOSE, 1);
	return puts(s);
}

length(n: ref Node, t: int): int
{
	i := 0;
	if(n.ntype == t){
		i++;
		i += length(n.left, t);
		i += length(n.right, t);
	}
	return i;
}

builtin_length(nil: ref Context, argv: list of ref Listnode, nil: int): string
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
	i := 0;
	if(n != nil && n.ntype == n_BLOCK){
		if(n.left == nil)
			i = 0;
		else if(n.left.ntype == n_SEQ){
			i = length(n.left, n_SEQ) + 1;
		}else if(n.left.ntype == n_ADJ){
			i = length(n.left, n_ADJ);
		}else
			i = 1;
	}
	s = string i + "\n";
	return puts(s);
}

part(n: ref Node, cnt: int, idx: list of int): (int, ref Node)
{
	nn: ref Node;
	if(n.ntype == n_SEQ || n.ntype == n_ADJ){
		(cnt, nn) = part(n.left, cnt, idx);
		if(nn != nil)
			return (cnt, nn);
		(cnt, nn) = part(n.right, cnt, idx);
		if(nn != nil)
			return (cnt, nn);
	}else 
		cnt++;
	if(cnt == hd idx){
		if(tl idx == nil)
			return (cnt, n);
	}
	return (cnt, nil);
}

builtin_part(ctxt: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n, nn: ref Node;
	s := "";
	if(len argv != 2)
		builtinusage(ctxt, "Part expr n");
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
	if(n != nil && n.ntype == n_BLOCK){
		(nil, nn) = part(n.left, 0, list2intlist(hd tl argv));
		if(nn != nil)
			s = cmd2string(nn) + "\n";
	}
	return puts(s);
}

list2intlist(ln: ref Listnode): list of int
{
	if(ln.cmd == nil)
		return int ln.word :: nil;
	n := ln.cmd;
	l := seq2list(n.left);
	nl :list of int;
	for(;l != nil; l = tl l)
		nl = int hd l :: nl;
	return nl;
}

seq2list(n: ref Node): list of string
{
	if(n.ntype == n_SEQ){
		sl := seq2list(n.left);
		sr := seq2list(n.right);
		sl = reverse(sl);
		for(;sl != nil; sl = tl sl)
			sr = hd sl :: sr;
		return sr;
	}
	else if(n.ntype == n_ADJ)
		return cmd2string(mk(n_BLOCK, n, nil)) :: nil;
	else
		return cmd2string(n) :: nil;
}

map(n: ref Node, f: string): string
{
	s: string;
	if(n.ntype == n_SEQ)
		s = map(n.left, f) + ";" + map(n.right, f);
	else if(n.ntype == n_ADJ)
		s = f + cmd2string(mk(n_BLOCK, n, nil));
	else
		s = f + cmd2string(n);
	return s;
}

builtin_map(c: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = evlis(c, tl argv);
	n: ref Node;
	s := "";
	if(len argv != 2)
		return "arg error";
	if((hd tl argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd tl argv).word, nil);
	else
		n = (hd tl argv).cmd;
	if(n != nil && n.ntype == n_BLOCK){
		s = "{" + map(n.left, (hd argv).word + " ") + "}\n";
	}
	return puts(s);
}

apply(n: ref Node): string
{
	s: string;
	if(n.ntype == n_SEQ)
		s = apply(n.left) + " " + apply(n.right);
	else if(n.ntype == n_ADJ)
		s = cmd2string(mk(n_BLOCK, n, nil));
	else
		s = cmd2string(n);
	return s;
}

builtin_apply(c: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = evlis(c, tl argv);
	n: ref Node;
	s := "";
	if(len argv != 2)
		return "arg error";
	if((hd tl argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd tl argv).word, nil);
	else
		n = (hd tl argv).cmd;
	if(n != nil && n.ntype == n_BLOCK){
		s = "{" + (hd argv).word + " " + apply(n.left) + "}\n";
	}
	return puts(s);
}

fullform(n: ref Node): string
{
	s: string;
	if(n.ntype == n_SEQ)
		s = fullform(n.left) + " " + fullform(n.right);
	else if(n.ntype == n_BLOCK)
		s = cmd2string(n);
	else if(n.ntype != n_WORD)
		s = cmd2string(mk(n_BLOCK, n, nil));
	else
		s = cmd2string(n);
	return s;
}

builtin_fullform(nil: ref Context, argv: list of ref Listnode, nil: int): string
{
	argv = tl argv;
	n: ref Node;
	s := "";
	if(len argv != 1)
		return "arg error";
	if((hd argv).cmd == nil)
		n = ref Node(n_WORD, nil, nil, (hd argv).word, nil);
	else
		n = (hd argv).cmd;
	if(n != nil && n.ntype == n_BLOCK){
		s = fullform(n.left) + "\n";
		if(n.left != nil && n.left.ntype == n_SEQ)
			s = "List " + s;
	}
	return puts(s);
}

builtin_rest(nil: ref Context, argv: list of ref Listnode, nil: int): string
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
	if(n == nil || n.ntype != n_BLOCK || n.left.ntype != n_SEQ)
		return nil;
	n = mk(n_BLOCK, n.left.right, nil);
	s = cmd2string(n) + "\n";
	return puts(s);
}

builtin_treeview(nil: ref Context, argv: list of ref Listnode, nil: int): string
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
	s = treeview(n, "") + "\n";
	return puts(s);
}

puts(s: string) : string
{
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

treeview(n: ref Node, xx: string): string
{
	if (n == nil)
		return "";

	sys->fprint(sys->fildes(2), "dbg: %s %s\n", typs[n.ntype], xx);
	s: string;
	case n.ntype {
	n_BLOCK =>	s = "{" + treeview(n.left, "left") + "}";
	n_VAR =>		s = "$" + treeview(n.left, "left");
				if (n.right != nil)
					s += "(" + treeview(n.right, "right") + ")";
	n_SQUASH =>	s = "$\"" + treeview(n.left, "left");
	n_COUNT =>	s = "$#" + treeview(n.left, "left");
	n_BQ =>		s = "`" + treeview(n.left, "left");
	n_BQ2 =>		s = "\"" + treeview(n.left, "left");
	n_LIST =>		s = "(" + treeview(n.left, "left") + ")";
	n_SEQ =>		s = treeview(n.left, "left") + ";" + treeview(n.right, "right");
	n_NOWAIT =>	s = treeview(n.left, "left") + "&";
	n_CONCAT =>	s = treeview(n.left, "left") + "^" + treeview(n.right, "right");
	n_ASSIGN =>	s = treeview(n.left, "left") + "=" + treeview(n.right, "right");
	n_LOCAL =>	s = treeview(n.left, "left") + ":=" + treeview(n.right, "right");
	n_ADJ =>		s = treeview(n.left, "left") + " " + treeview(n.right, "right");
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

runasync(ctxt: ref Context, cmd : list of ref Listnode, out: array of ref Sys->FD, sync: chan of string)
{
	ctxt = ctxt.copy(1);
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(out[1].fd, 1);
	out[0] = nil;
	out[1] = nil;
	sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: ctxt.waitfd.fd :: nil);
	sync <-= nil;
#	status := sh->run(nil, list2stringlist(cmd));
	status := ctxt.run(cmd, 0);
	sys->pctl(Sys->NEWFD, nil);
	sync <-= status;
}

bq(ctxt: ref Context, cmd: list of ref Listnode, seps: string): (list of ref Listnode, string)
{
	fds := array[2] of ref Sys->FD;
	if (sys->pipe(fds) == -1)
		ctxt.fail("no pipe", sys->sprint("sh: cannot make pipe: %r"));

	startchan := chan of string;
	spawn runasync(ctxt, cmd, (array[2] of ref Sys->FD)[0:] = fds, startchan);
	<-startchan;
	fds[1] = nil;
	bqlist := getbq(ctxt, fds[0], seps);
	st := <-startchan;
	if(st != nil)
		return (nil, st);
	return (bqlist, nil);
}

getbq(nil: ref Context, fd: ref Sys->FD, seps: string): list of ref Listnode
{
	buf := array[Sys->ATOMICIO] of byte;
	buflen := 0;
	while ((n := sys->read(fd, buf[buflen:], len buf - buflen)) > 0) {
		buflen += n;
		if (buflen == len buf) {
			nbuf := array[buflen * 2] of byte;
			nbuf[0:] = buf[0:];
			buf = nbuf;
		}
	}
	l: list of string;
	if (seps != nil)
		(nil, l) = sys->tokenize(string buf[0:buflen], seps);
	else
		l = string buf[0:buflen] :: nil;
	buf = nil;
	return stringlist2list(l);
}

waitfor(ctxt: ref Context, pids: list of int): string
{
	if (pids == nil)
		return nil;
	status := array[len pids] of string;
	wcount := len status;
	buf := array[Sys->WAITLEN] of byte;
	onebad := 0;
	for(;;){
		n := sys->read(ctxt.waitfd, buf, len buf);
		if(n < 0)
			sys->fprint(stderr, "error on wait read: %r");
		(who, line, s) := parsewaitstatus(ctxt, string buf[0:n]);
		if (s != nil) {
			if (len s >= 5 && s[0:5] == "fail:")
				s = s[5:];
			else
				sys->fprint(stderr, "%s\n", line);
		}
		for ((i, pl) := (0, pids); pl != nil; (i, pl) = (i+1, tl pl))
			if (who == hd pl)
				break;
		if (i < len status) {
			# wait returns two records for a killed process...
			if (status[i] == nil || s != "killed") {
				onebad += s != nil;
				status[i] = s;
				if (wcount-- <= 1)
					break;
			}
		}
	}
	if (!onebad)
		return nil;
	r := status[len status - 1];
	for (i := len status - 2; i >= 0; i--)
		r += "|" + status[i];
	return r;
}

parsewaitstatus(ctxt: ref Context, status: string): (int, string, string)
{
	for (i := 0; i < len status; i++)
		if (status[i] == ' ')
			break;
	if (i == len status - 1 || status[i+1] != '"')
		ctxt.fail("bad wait read",
			sys->sprint("sh: bad exit status '%s'", status));

	for (i+=2; i < len status; i++)
		if (status[i] == '"')
			break;
	if (i > len status - 2 || status[i+1] != ':')
		ctxt.fail("bad wait read",
			sys->sprint("sh: bad exit status '%s'", status));

	return (int status, status, status[i+2:]);
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

varfind(name: string): ref Definition
{
	idx := hashfn(name, len defs);
	for (vl := defs[idx]; vl != nil; vl = tl vl)
		if ((hd vl).name == name)
			return hd vl;
	return nil;
}
