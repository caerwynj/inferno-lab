# markov chain program
# (chapter 3, The Practice of Programming)
implement Markov;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
	
include "rand.m";
	rand : Rand;
include "keyring.m";
include "security.m";

include "arg.m";
	arg: Arg;

Markov: module
{
	NPREF : con 2;
	NHASH: con 4093;
	MAXGEN: con 10000;
	MULTIPLIER: con 31;
	NOWORD: con "\n";
	
	State: adt 
	{
		pref: array of string;
		suf: list of string;
	};
	
	
	init:	fn(ctxt: ref Draw->Context, argl: list of string);
};

statetab:= array[NHASH] of list of ref State;	# hash table of states

init(nil: ref Draw->Context, args: list of string)
{
 	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	rand = load Rand Rand->PATH;
	random := load Random Random->PATH;
	rand->init(random->randomint(Random->ReallyRandom));
	arg = load Arg Arg->PATH;
	
	interact: int;
	ifile: string;
	nwords, i: int = MAXGEN;
	prefix := array[NPREF] of string;	# current input prefix
	bin := bufio->fopen(sys->fildes(0), Bufio->OREAD);

	for (i=0; i < NPREF; i++) # set up innitial prefix
		prefix[i] = NOWORD;

	arg->init(args);
	while((c := arg->opt()) != 0)
	case c {
		'i' => 
			interact = 1;
			ifile = arg->arg();
		* =>   sys->print("unknown option (%c)\n", c);
	}
	args = arg->argv();

	build(prefix, bin);
	add(prefix, NOWORD);
	
	#printtable(statetab,0,len statetab);
	generate(nwords);
}

abs(n: int): int
{
	if(n < 0)
		return -n;
	return n;
}

printlist(ls: list of string)
{
	nls := ls;
	for (i:=0; i < len ls; i++){
		sys->print("%s, ", hd nls);
		nls = tl nls;
	}
	sys->print("\n");
}

printtable(stab: array of list of ref State, begin: int, end: int)
{
	for (i:= begin; i < end; i++)
	{
		st := stab[i]; nst :=0;
		while (st != nil)
		{
			sys->print("stab[%d] %d/%d", i, nst++,len st);
			s:= hd st;
			sys->print("\n	pref[%d]: ", len s.pref);
			for (k:=0; k < NPREF; k++)
				 sys->print("%s ", s.pref[k]);
			
			sys->print("\n	suf[%d]: ", len s.suf);
			sl := s.suf;
			for (j:=0; j < len sl; j++){
				 sys->print("%s ", hd sl);
				 sl = tl sl;
			}
			sys->print("\n");
			st = tl st;
		}
	}
}

build(prefix: array of string, bf: ref Iobuf)
{
	sep: string = "	 \n";
	while( (ws := bf.gett(sep)) != nil){
		(ntok,tok) := sys->tokenize(ws,sep);
		if (ntok > 0)
			add(prefix, hd tok);
	}
}

addtotail(as: array of string, s: string)
{
	for (i := 0; i < len as-1; i++)
		as[i] = as[i+1];
	as[NPREF-1] = s;
}
add (prefix: array of string, suffix: string)
{
	sp : ref State;
	
	sp = lookup (prefix, 1);	# create if not found
	sp.suf =  addsuffix(sp, suffix);
	addtotail(prefix, suffix);	# move the words down the prefix
}

addsuffix(sp: ref State, suffix: string): list of string
{
	return suffix :: sp.suf;
}

hash(s: array of string) : int
{
	h: int;
	
	if (len s != NPREF)
		raise "hash: error";

	h = 0;
	for (i :=0; i < NPREF; i++)
		for (j := 0; j < len s[i]; j++)
			h = abs(MULTIPLIER * h + s[i][j]);
	return h % NHASH;
}

# lookup: search for prefix; create if requested
# returns pointer if present or created; nil if not;
# creation doesn't 
lookup (prefix: array of string, create: int): ref State
{
	i, h : int;
	sp : ref State;
	
	h = hash(prefix);
	#sys->print("lookup (%s %s,%d) = %d\n", prefix[0], prefix[NPREF-1], create, h);
	for (stl := statetab[h]; stl  != nil; stl = tl stl){
		sp = hd stl;
		for (i = 0; i < NPREF; i++)
			if (prefix[i]  != sp.pref[i])
				break;
		if (i == NPREF)	# found it
			return sp;
	}
	
	if (create){
		sp = ref State;
		npref := array[NPREF] of string;

		sp.pref = npref;
		for (i=0; i <NPREF; i++)
			sp.pref[i] = prefix[i];
		statetab[h] = sp :: statetab[h];
	}
	return sp;
}

generate(nwords: int)
{
	sp: ref State;
	sl: list of string;
	suf: string;
	
	w: string;
	prefix := array[NPREF] of string;
	i, nmatch : int;
	
	for (i = 0; i < NPREF; i++) # reset initial prefix
		prefix[i] = NOWORD;
	
	for (i = 0; i < nwords; i++) {
		sp = lookup(prefix, 0);
		nmatch = 0;
		for (sl = sp.suf; sl != nil; sl = tl sl){
			suf = hd sl;
			if ((rand->rand(2^31-1) % ++nmatch)  == 0)	# prob = 1/nmatch
				w = suf;
		}
		
		if(w == NOWORD)
			break;
		
		sys->print("%s\n",w);
		addtotail(prefix, w);
	}
}
