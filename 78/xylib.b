implement Xylib;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "xylib.m";


valuec := array[] of {
	tagof(Value.O) => 'o',
	tagof(Value.S) => 's',
	tagof(Value.C) => 'c',
	tagof(Value.N) => 'n',
	tagof(Value.F) => 'f',
};

init()
{
	sys = load Sys Sys->PATH;
}

Value.getfd(v: self ref Value):ref Sys->FD
{
	pick xv := v{
	O =>
		replyc := chan of ref Value;
		xv.i <-= ref Value.O(replyc);
		return (<-replyc).getfd();
	F =>
		return xv.i;
	}
	raise typeerror('f', v);
}

Value.gets(v: self ref Value): string
{
	if(v == nil)
		return nil;
	pick xv := v {
	O =>
		replyc := chan of ref Value;
		xv.i <-= ref Value.O(replyc);
		return (<-replyc).gets();
	S =>
		return xv.i;
	}
	raise typeerror('s', v);
}

Value.getn(v: self ref Value): int
{
	pick xv := v {
	O =>
		replyc := chan of ref Value;
		xv.i <-= ref Value.O(replyc);
		return (<-replyc).getn();
	N =>
		return xv.i;
	}
	raise typeerror('n', v);
}

Value.send(v: self ref Value, r: ref Value)
{
	pick xv := v {
	O =>
		xv.i <-= r;
		return;
	}
	raise typeerror('o', v);
}

type2s(c: int): string
{
	case c{
	'a' =>
		return "any";
	's' =>
		return "string";
	'v' =>
		return "void";
	'c' =>
		return "command";
	'f' =>
		return "filedescriptor";
	'n' =>
		return "number";
	'o' =>
		return "channel";
	* =>
		return sys->sprint("unknowntype('%c')", c);
	}
}

typeerror(tc: int, v: ref Value): string
{
	sys->fprint(sys->fildes(2), "fs: bad type conversion, expected %s, was actually %s\n", type2s(tc), type2s(valuec[tagof v]));
	return "type conversion error";
}

Value.discard(v: self ref Value)
{
	if(v == nil)
		return;
	pick xv := v {
	O =>
		xv.i <-= nil;
	}
}

Value.typec(v: self ref Value): int
{
	return valuec[tagof v];
}

# true if a module with type sig t1 is compatible with a caller that expects t0
typecompat(t0, t1: string): int
{
	(rt0, at0, ot0) := splittype(t0);
	(rt1, at1, ot1) := splittype(t1);
	if((rt0 != rt1 && rt0 != 'a') || at0 != at1)		# XXX could do better for repeated args.
		return 0;
	for(i := 1; i < len ot0; i++){
		for(j := i; j < len ot0; j++)
			if(ot0[j] == '-')
				break;
		(ok, t) := opttypes(ot0[i], ot1);
		if(ok == -1 || ot0[i:j] != t)
			return 0;
		i = j + 1;
	}
	return 1;
}

splittype(t: string): (int, string, string)
{
	if(t == nil)
		return (-1, nil, nil);
	for(i := 1; i < len t; i++)
		if(t[i] == '-')
			break;
	return (t[0], t[1:i], t[i:]);
}

opttypes(opt: int, opts: string): (int, string)
{
	for(i := 1; i < len opts; i++){
		if(opts[i] == opt && opts[i-1] == '-'){
			for(j := i+1; j < len opts; j++)
				if(opts[j] == '-')
					break;
			return (0, opts[i+1:j]);
		}
	}
	return (-1, nil);
}

cmdusage(s, t: string): string
{
	if(s == nil)
		return nil;
	for(oi := 0; oi < len t; oi++)
		if(t[oi] == '-')
			break;
	if(oi < len t){
		single, multi: string;
		for(i := oi; i < len t - 1;){
			for(j := i + 1; j < len t; j++)
				if(t[j] == '-')
					break;

			optargs := t[i+2:j];
			if(optargs == nil)
				single[len single] = t[i+1];
			else{
				multi += sys->sprint(" [-%c", t[i+1]);
				for (k := 0; k < len optargs; k++)
					multi += " " + type2s(optargs[k]);
				multi += "]";
			}
			i = j;
		}
		if(single != nil)
			s += " [-" + single + "]";
		s += multi;
	}
	multi := 0;
	if(oi > 2 && t[oi - 1] == '*'){
		multi = 1;
		oi -= 2;
	}
	for(k := 1; k < oi; k++)
		s += " " + type2s(t[k]);
	if(multi)
		s += " [" + type2s(t[k]) + "...]";
	s += " -> " + type2s(t[0]);
	return s;
}
