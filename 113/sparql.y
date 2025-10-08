%{
include "sys.m";
sys: Sys;
include "draw.m";
include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;
include "regex.m";
regex: Regex;
Re: import regex;
include "string.m";
str: String;
include "triplestore.m";
triplestore: Triplestore;
Triple: import triplestore;

YYSTYPE: adt {
	s: string;
	lt: list of Triple;
	ls: list of string;
	props: list of Props;
};
YYLEX: adt {
	lval: YYSTYPE;
	lex: fn(l: self ref YYLEX): int;
	error: fn(l: self ref YYLEX, msg: string);
};
%}

%module Sparql{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
}

%token <s> IRI LDQ LSQ QUOT PREF BLANK BASE NAME PNAME BOOL LANG DOT SELECT WHERE VAR1 VAR2
%token <s> NUM
%type <s> object
%type <s> graphTerm varOrTerm varOrIri graphNode var
%type <s> verb iri
%type <lt> triplesBlock groupGraphPattern whereClause triplesSameSubject
%type <ls> objectList selectClause varList
%type <props> propertyList
%left ';'

%start query

%%
query: 		prologue selectQuery

prologue: 	
		| baseDecl prologue
		| prefixDecl prologue

baseDecl: 	BASE IRI 	{baseuri = expand($2); }

prefixDecl: 	PREF PNAME IRI 	{prefixes = ($2, expand($3)) :: prefixes; }

selectQuery: 	selectClause whereClause  {query($1, $2);}

selectClause: 	SELECT varList  	{$$ = $2;}
		| SELECT '*'		{$$ = nil;}

varList:	var			{$$ = $1 :: $$;}
		| varList var		{$$ = $2 :: $$;}

whereClause: 	WHERE groupGraphPattern  {$$ = $2;}

groupGraphPattern: '{' triplesBlock '}'  {$$ = $2;}

triplesBlock:  	triplesSameSubject	{$$ = $1;}
		| triplesBlock '.' triplesSameSubject	{$$ = append($1, $3);}

triplesSameSubject:  varOrTerm propertyList {$$ = mktriple($1, $2); }

propertyList: 	verb objectList 	{$$ = Props($1, $2) :: nil;} 
		| propertyList ';' verb objectList 	{$$ = Props($3, $4) :: $1;}

verb: 		varOrIri
		| 'a'  			{$$ = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";}

objectList:	object 			{$$ = $1 :: nil;}
		| objectList ',' object  {$$ = $3 :: $1;}

object:		graphNode  		{$$ = $1;}

graphNode:	varOrTerm

varOrIri:	var	
		| iri			{$$ = expand($1);}

iri:		IRI
		| PNAME
		| NAME
		| BLANK

varOrTerm:	var	
		| graphTerm

graphTerm: 	iri			{$$ = expand($1);}
		| NUM
		| BOOL	
		| LDQ	
		| QUOT	
		| LSQ

var : 	 	VAR1	
		| VAR2	
%%

in: ref Iobuf;
stderr: ref Sys->FD;

tok: string;
toktyp: int;
line: string;
io: ref Iobuf;
prefixes: list of (string, string);
baseuri: string;
emptyprefix: string;
linecount := 0;
subject, predicate: list of string;  # Stack
blankcount := 0;
bpref := "_:zxcv";
DEBUG: con 0;
triples : list of ref Triple;
bgp: list of Triple;

#IRI, LDQ, LSQ, QUOT, NUM, PREF, BLANK, BASE, NAME, PNAME, BOOL, LANG, DOT: con iota;
re_list: list of (Re, int);

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	stderr = sys->fildes(2);
	regex = load Regex Regex->PATH;
	str = load String String->PATH;
	triplestore = load Triplestore Triplestore->PATH;
	argv = tl argv;
	
	if(len argv != 2){
		sys->print("error args\n");
		exit;
	}
	triplestore->open(hd argv);
	argv = tl argv;
	in = bufio->open(hd argv, Bufio->OREAD);

	e: string;
	re: Re;
	res := list of {
		("^<[A-Za-z0-9_:%/#\\.\\-~&+=?,]+>", IRI),
		("^\"\"\"", LDQ),
		("^'''", LSQ),
		("^\"(([^\"])|(\\\"))*\"", QUOT),
		("^[0-9]+", NUM),
		("^(@prefix|PREFIX)", PREF),
		("^_:[a-z0-9]+", BLANK),
		("^(@base|BASE)", BASE),
		("^SELECT", SELECT),
		("^WHERE", WHERE),
		("^\\?[a-zA-Z0-9-]+", VAR1),
		("^\\$[a-zA-Z0-9-]+", VAR2),
		("^:[a-zA-Z0-9]*", NAME),
		("^[a-zA-Z0-9]+:[a-zA-Z0-9]*", PNAME),
		("^(true|false)", BOOL),
		("^@[a-zA-Z]+", LANG),
		("^[.;,a\\[\\](){}]", DOT),
	};
	for(l := res; l != nil; l = tl l) {
		(re, e) = regex->compile((hd l).t0, 0);
		re_list = (re, (hd l).t1) :: re_list;
	}
	# reverse the list
	rl : list of (Re, int);
	for (ll := re_list; ll != nil; ll = tl ll)	
		rl = hd ll :: rl;
	re_list = rl;
	lex := ref YYLEX;
	yyparse(lex);
}

YYLEX.error(nil: self ref YYLEX, err: string)
{
	sys->fprint(stderr, "line %d, tok %s, typ %d, %s, rest:%s\n", linecount, tok, toktyp, err, line);
}

YYLEX.lex(lx: self ref YYLEX): int
{
	lx.lval.s = advance(lx);
	if(toktyp == DOT)
		return tok[0];
	return toktyp;
}

advance(lx: ref YYLEX): string
{
	a: array of (int,int);

	if (tok == "(eof)") {
		toktyp = 0;
		return "(eof)";
	}
	line = str->drop(line, " \t\n");
	while(len line == 0) {
		if ((line = in.gets('\n')) == nil) {
			tok = "(eof)";
			toktyp = 0;
			return tok;
		}
		linecount++;
		line = str->drop(line, " \t\n");
		if (len line > 0 && line[0] == '#')
			line = "";
	}

	for(l := re_list; l != nil; l = tl l) {
		(re, typ) := hd l;
		a = regex->execute(re, line);
		if(a != nil) {
			(beg,end) := a[0];
			tok = line[beg:end];
			toktyp = typ;
			line = line[end:];
			if (len line > 0 && line[0] == '#')
				line = "";
			if(DEBUG)sys->print("advance:%d %s typ %d\n", linecount, tok, typ);
			return tok;
		}
	}
	lx.error("advance() unrecognized token: " + tok + line);
	tok = "(eof)";
	toktyp = 0;
	return tok;
}

Props: adt {
	verb: string;
	obj: list of string;
};

mktriple(sub: string, props: list of Props): list of Triple
{
	t: list of Triple;

	if(DEBUG)sys->print("mktriple %d\n", len props);
	for(p := props; p != nil; p = tl p) {
		verb := (hd p).verb;
		if(DEBUG)sys->print("mktriple nobjs %d\n", len (hd p).obj);
		for(l := (hd p).obj; l != nil; l = tl l)
			t = Triple(sub, verb, hd l) :: t;
	}
	return t;
}

prtriple(lt: list of Triple)
{
	for(l := lt; l != nil; l = tl l) {
		(s, p, o) := hd l;
		sys->print("%s %s %s\n", s, p, o);
	}
}

append(la, lb: list of Triple): list of Triple
{
	r: list of Triple;
	for(; la != nil; la = tl la)
		r = hd la :: r;
	for(; lb != nil; lb = tl lb)
		r = hd lb :: r;
	return r;
}

expand(s: string): string
{
	if(s[0] == ':') 
		s = emptyprefix + s[1:];
	else if(s[0] == '<') {
		s = s[1:len s - 1];
		if(!str->prefix("http", s)) {
			s = baseuri + s;
		}
	} else if(s[0] == '_')
		;
	else {
		(l, r) := str->splitr(s, ":");
		if(DEBUG)sys->print("iri: %s\n", tok);
		pre := find(l);
		if(pre == nil) {
			sys->fprint(stderr, "warn: prefix not found: %s\n", l);
		}
		s = pre + r;
	}
	return s;
}

find(pre: string): string
{
	for(l := prefixes; l != nil; l = tl l) {
		(p, s) := hd l;
		if(DEBUG)sys->print("%s\n", p + pre);
		if(p == pre)
			return s;
	}
	return nil;
}

query(sel: list of string, whe: list of Triple)
{
	if(DEBUG) {
		sys->print("Query\n");
		for (ls := sel; ls != nil; ls = tl ls)
			sys->print("q: %s\n", hd ls);
		sys->print("Where\n");
		prtriple(whe);
		sys->print("end where\n");
	}
	stmt := triplestore->prepare(sel, whe);
	while((result := triplestore->step(stmt)) != nil) {
		for(l := result; l != nil; l = tl l)
			sys->print("%s,", hd l); 
		sys->print("\n");
	}
}
