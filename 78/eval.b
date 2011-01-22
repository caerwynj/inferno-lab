implement Eval;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context: import sh;
include "readdir.m";
include "xylib.m";
	xylib: Xylib;
	Value, type2s, Option: import xylib;

Eval: module {
	types: fn(): string;
	init:	fn();
	run: fn(r: chan of ref Xylib->Value, 
		opts: list of Xylib->Option, args: list of ref Xylib->Value);
	eval: fn(expr: string, args: list of ref Xylib->Value, ret: int): ref Xylib->Value;
};

WORD, SHCMD, VAR: con iota;

Evalstate: adt {
	s:	string;
	spos: int;
	args: array of ref Value;
	verbose: int;

	expr: fn(p: self ref Evalstate): ref Value;
	getc: fn(p: self ref Evalstate): int;
	ungetc: fn(p: self ref Evalstate);
	gettok: fn(p: self ref Evalstate): (int, string);
};

ops: list of (string, Xymodule);
lock: chan of int;

# to do:
# - change value letters to more appropriate (e.g. fs->f, entries->e, gate->g).
# - allow shell $variable expansions

types(): string
{
	return "os-v";
}

badmod(p: string)
{
	sys->fprint(sys->fildes(2), "fs: eval: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
	if(xylib == nil)
		badmod(Xylib->PATH);
	xylib->init();
	lock = chan[1] of int;
}

run(r: chan of ref Xylib->Value, opts: list of Option, args: list of ref Value)
{
	if((replyc := <-r) != nil){
		o := (ref Evalstate((hd args).gets(), 0, nil, opts != nil)).expr();
		replyc.send(o);
	}
}

eval(expr: string, args: list of ref Value, rtype: int): ref Value
{
	a := array[len args] of ref Value;
	for(i := 0; args != nil; args = tl args)
		a[i++] = hd args;
	e := ref Evalstate(expr, 0, a, 0);
	v := e.expr();
	vl: list of ref Value;
	for(i = 0; i < len a; i++)
		if(a[i] != nil)
			vl = a[i] :: vl;
	nv := cvt(e, v, rtype);
	if(nv == nil){
		vl = v :: vl;
		sys->fprint(stderr(), "fs: eval fn: %s cannot be converted to %s\n",
			type2s(v.typec()), type2s(rtype));
	}
	if(vl != nil)
		spawn discard(nil, vl);
	return nv;
}

tok2s(t: int, s: string): string
{
	case t {
	WORD =>
		return s;
	SHCMD =>
		return "@";
	VAR =>
		return "$" + s;
	}
	return sys->sprint("%c", t);
}

# expr: WORD exprs
# exprs:
#	| exprs '{' expr '}'
#	| exprs WORD
#	| exprs SHCMD
#	| exprs VAR
Evalstate.expr(p: self ref Evalstate): ref Value
{
	args: list of ref Value;
	t: int;
	s: string;
	{
		(t, s) = p.gettok();
	} exception {
	"parse error" =>
		return nil;
	}
	if(t != WORD){
		sys->fprint(stderr(), "fs: eval: syntax error (char %d), expected word, found %#q\n",
				p.spos, tok2s(t, s));
		return nil;
	}
	cmd := s;
loop:
	for(;;){
		{
			(t, s) = p.gettok();
		} exception {
		"parse error" =>
			spawn discard(nil, args);
			return nil;
		}
		case t {
		'{' =>
			v := p.expr();
			if(v == nil){
				spawn discard(nil, args);
				return nil;
			}
			args = v :: args;
		'}' =>
			break loop;
		WORD =>
			args = ref Value.S(s) :: args;
		VAR =>
			n := int s;
			if(n < 0 || n >= len p.args){
				sys->fprint(stderr(), "fs: eval: invalid arg reference $%s\n", s);
				spawn discard(nil, args);
				return nil;
			}
			if(p.args[n] == nil){
				sys->fprint(stderr(), "fs: eval: cannot use $%d twice\n", n);
				spawn discard(nil, args);
				return nil;
			}
			args = p.args[n] :: args;
			p.args[n] = nil;
		SHCMD =>
			if(sh == nil && (sh = load Sh Sh->PATH) == nil){
				sys->fprint(stderr(), "fs: eval: cannot load %s: %r\n", Sh->PATH);
				spawn discard(nil, args);
				return nil;
			}
			(c, err) := sh->parse(s);
			if(c == nil){
				sys->fprint(stderr(), "fs: eval: cannot parse shell command @%s: %s\n", s, err);
				spawn discard(nil, args);
				return nil;
			}
			args = ref Value.C(c) :: args;
		-1 =>
			break loop;
		* =>
			spawn discard(nil, args);
			sys->fprint(stderr(), "fs: eval: syntax error; unexpected token %d before char %d\n", t, p.spos);
			return nil;
		}
	}
	return runcmd(p, cmd, rev(args));
}

runcmd(p: ref Evalstate, cmd: string, args: list of ref Value): ref Value
{
	m := loadmodule(cmd);
	if(m == nil){
		spawn discard(nil, args);
		return nil;
	}
	otype := m->types();
	ok: int;
	opts: list of Option;
	(ok, opts, args) = cvtargs(p, args, cmd, otype);
	if(ok == -1){
		sys->fprint(stderr(), "fs: eval: usage: %s\n", xylib->cmdusage(cmd, otype));
		spawn discard(opts, args);
		return nil;
	}
	r := chan of ref Value;
	spawn m->run(r, opts, args);
	return ref Value.O(r);
}

cvtargs(e: ref Evalstate, args: list of ref Value, cmd, otype: string): (int, list of Option, list of ref Value)
{
	ok: int;
	opts: list of Option;
	(nil, at, t) := xylib->splittype(otype);
	(ok, opts, args) = cvtopts(e, t, cmd, args);
	if(ok == -1)
		return (-1, opts, args);
	if(len at < 1 || at[0] == '*'){
		sys->fprint(stderr(), "fs: eval: invalid type descriptor %#q for %#q\n", at, cmd);
		return (-1, opts, args);
	}
	n := len args;
	if(at[len at - 1] == '*'){
		tc := at[len at - 2];
		at = at[0:len at - 2];
		for(i := len at; i < n; i++)
			at[i] = tc;
	}
	if(n != len at){
		sys->fprint(stderr(), "fs: eval: wrong number of arguments to %#q\n", cmd);
		return (-1, opts, args);
	}
	d: list of ref Value;
	(ok, args, d) = cvtvalues(e, at, cmd, args);
	if(ok == -1)
		args = join(args, d);
	return (ok, opts, args);
}

cvtvalues(e: ref Evalstate, t: string, cmd: string, args: list of ref Value): (int, list of ref Value, list of ref Value)
{
	cargs: list of ref Value;
	for(i := 0; i < len t; i++){
		tc := t[i];
		if(args == nil){
			sys->fprint(stderr(), "fs: eval: %q missing argument of type %s\n", cmd, type2s(tc));
			return (-1, cargs, args);
		}
		v := cvt(e, hd args, tc);
		if(v == nil){
			sys->fprint(stderr(), "fs: eval: %q: %s cannot be converted to %s\n",
				cmd, type2s((hd args).typec()), type2s(tc));
			return (-1, cargs, args);
		}
		cargs = v :: cargs;
		args = tl args;
	}
	return (0, rev(cargs), args);
}

cvtopts(e: ref Evalstate, opttype: string, cmd: string, args: list of ref Value): (int, list of Option, list of ref Value)
{
	if(opttype == nil)
		return (0, nil, args);
	opts: list of Option;
getopts:
	while(args != nil){
		s := "";
		pick v := hd args {
		S =>
			s = v.i;
			if(s == nil || s[0] != '-' || len s == 1)
				s = nil;
			else if(s == "--"){
				args = tl args;
				s = nil;
			}
		}
		if(s == nil)
			return (0, opts, args);
		s = s[1:];
		while(len s > 0){
			opt := s[0];
			if(((ok, t) := xylib->opttypes(opt, opttype)).t0 == -1){
				sys->fprint(stderr(), "fs: eval: %s: unknown option -%c\n", cmd, opt);
				return (-1, opts, args);
			}
			if(t == nil){
				s = s[1:];
				opts = (opt, nil) :: opts;
			}else{
				if(len s > 1)
					args = ref Value.S(s[1:]) :: tl args;
				else
					args = tl args;
				vl: list of ref Value;
				(ok, vl, args) = cvtvalues(e, t, cmd, args);
				if(ok == -1)
					return (-1, opts, join(vl, args));
				opts = (opt, vl) :: opts;
				continue getopts;
			}
		}
		args = tl args;
	}
	return (0, opts, args);
}

discard(ol: list of (int, list of ref Value), vl: list of ref Value)
{
	for(; ol != nil; ol = tl ol)
		for(ovl := (hd ol).t1; ovl != nil; ovl = tl ovl)
			vl = (hd ovl) :: vl;
	for(; vl != nil; vl = tl vl)
		(hd vl).discard();
}

loadmodule(cmd: string): Xymodule
{
	lock <-= 0;
	for(ol := ops; ol != nil; ol = tl ol)
		if((hd ol).t0 == cmd)
			break;
	if(ol != nil){
		<-lock;
		return (hd ol).t1;
	}
	p := cmd + ".dis";
	if(p[0] != '/' && !(p[0] == '.' && p[1] == '/'))
		p = "/dis/xy/" + p;
	m := load Xymodule p;
	if(m == nil){
		sys->fprint(stderr(), "fs: eval: cannot load %s: %r\n", p);
		sys->fprint(stderr(), "fs: eval: unknown verb %#q\n", cmd);
		sys->werrstr(sys->sprint("cannot load module %q", cmd));
		<-lock;
		return nil;
	}
	{
		m->init();
	} exception e {
	"fail:*" =>
		<-lock;
		sys->werrstr(sys->sprint("module init failed: %s", e[5:]));
		return nil;
	}
	ops = (cmd, m) :: ops;
	<-lock;
	return m;
}

runexternal(nil: ref Evalstate, cmd: string, t: string, opts: list of Option, args: list of ref Value): ref Value
{
	m := loadmodule(cmd);
	if(m == nil)
		return nil;
	if(!xylib->typecompat(t, m->types())){
		sys->fprint(stderr(), "fs: eval: %s has incompatible type\n", cmd);
		sys->fprint(stderr(), "fs: eval: expected usage: %s\n", xylib->cmdusage(cmd, t));
		sys->fprint(stderr(), "fs: eval: actually usage: %s\n", xylib->cmdusage(cmd, m->types()));
		return nil;
	}
	r := chan of ref Value;
	spawn m->run(r, opts, args);
	return ref Value.O(r);
}

cvt(e: ref Evalstate, v: ref Value, t: int): ref Value
{
	{
		return cvt1(e, v, t);
	} exception {
	"type conversion" =>
		return nil;
	}
}

cvt1(e: ref Evalstate, v: ref Value, t: int): ref Value
{
	if(v.typec() == 'o' || v.typec() == t)
		return v;
	r: ref Value;
	case t {
	's' =>
		r = runexternal(e, "run", "sc", nil, cvt1(e, v, 'c') :: nil);
	}
	if(r == nil)
		raise "type conversion";
	return r;
}

Evalstate.getc(p: self ref Evalstate): int
{
	c := -1;
	if(p.spos < len p.s)
		c = p.s[p.spos];
	p.spos++;
	return c;
}

Evalstate.ungetc(p: self ref Evalstate)
{
	p.spos--;
}

# XXX backslash escapes newline?
Evalstate.gettok(p: self ref Evalstate): (int, string)
{
	while ((c := p.getc()) == ' ' || c == '\t')
		;
	t: int;
	s: string;

	case c {
	-1 =>
		t = -1;
	'\n' =>
		t = '\n';
	'{' =>
		t = '{';
	'}' =>
		t = '}';
	'@' =>		# embedded shell command
		while((nc := p.getc()) == ' ' || nc == '\t')
			;
		if(nc != '{'){
			sys->fprint(stderr(), "fs: eval: expected '{' after '@'\n");
			raise "parse error";
		}
		s = "{";
		d := 1;
	getcmd:
		while((nc = p.getc()) != -1){
			s[len s] = nc;
			case nc {
			'{' =>
				d++;
			'}' =>
				if(--d == 0)
					break getcmd;
			'\'' =>
				s += getqword(p, 1);
			}
		}
		if(nc == -1){
			sys->fprint(stderr(), "fs: eval: unbalanced '{' in shell command\n");
			raise "parse error";
		}
		t = SHCMD;
	'$' =>
		t = VAR;
		s = getvar(p);
	'\'' =>
		s = getqword(p, 0);
		t = WORD;
	* =>
		do {
			s[len s] = c;
			c = p.getc();
			if (in(c, " \t{}\n")){
				p.ungetc();
				break;
			}
		} while (c >= 0);
		t = WORD;
	}
	return (t, s);
}

getvar(p: ref Evalstate): string
{
	c := p.getc();
	if(c == -1){
		sys->fprint(stderr(), "fs: eval: unexpected eof after '$'\n");
		raise "parse error";
	}
	v: string;
	while(in(c, " \t\n@{}'") == 0){
		v[len v] = c;
		c = p.getc();
	}
	p.ungetc();
	for(i := 0; i < len v; i++)
		if(v[i] < '0' || v[i] > '9')
			break;
	if(i < len v || v == nil){
		sys->fprint(stderr(), "fs: eval: invalid $ reference $%q\n", v);
		raise "parse error";
	}
	return v;
}

in(c: int, s: string): int
{
	for(i := 0; i < len s; i++)
		if(s[i] == c)
			return 1;
	return 0;
}

# get a quoted word; the starting quote has already been seen
getqword(p: ref Evalstate, keepq: int): string
{
	s := "";
	for(;;) {
		while ((nc := p.getc()) != '\'' && nc >= 0)
			s[len s] = nc;
		if (nc == -1){
			sys->fprint(stderr(), "fs: eval: unterminated quote\n");
			raise "parse error";
		}
		if (p.getc() != '\'') {
			p.ungetc();
			if(keepq)
				s[len s] = '\'';
			return s;
		}
		s[len s] = '\'';	# 'xxx''yyy' becomes WORD(xxx'yyy)
		if(keepq)
			s[len s] = '\'';
	}
}

rev[T](x: list of T): list of T
{
	l: list of T;
	for(; x != nil; x = tl x)
		l = hd x :: l;
	return l;
}

# join x to y, leaving result in arbitrary order.
join[T](x, y: list of T): list of T
{
	if(len x > len y)
		(x, y) = (y, x);
	for(; x != nil; x = tl x)
		y = hd x :: y;
	return y;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
