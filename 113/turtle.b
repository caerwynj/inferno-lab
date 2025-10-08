implement Turtle;
include "sys.m";
sys: Sys;
include "turtle.m";
include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;
include "regex.m";
regex: Regex;
Re: import regex;
include "string.m";
str: String;

tok: string;
toktyp: int;
line: string;
io: ref Iobuf;
triplestore: list of ref Triple;
prefixes: list of (string, string);
baseuri: string;
emptyprefix: string;
linecount := 0;
subject, predicate: list of string;  # Stack
blankcount := 0;
bpref := "_:zxcv";
DEBUG: con 0;

IRI, LDQ, LSQ, QUOT, 
NUM, PREF, BLANK, 
BASE, NAME, PNAME, BOOL, 
LANG, DOT: con iota;
re_list: list of (Re, int);

init()
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	regex = load Regex Regex->PATH;
	str = load String String->PATH;

	e: string;
	re: Re;
	res := list of {
		"^<[A-Za-z0-9_:%/#\\.\\-~&+=?,]+>",
		"^\"\"\"",
		"^'''",
		"^\"(([^\"])|(\\\"))*\"",
		"^[0-9.]+",
		"^@prefix",
		"^_:[a-z0-9]+",
		"^@base",
		"^:[a-zA-Z0-9]*",
		"^[a-zA-Z0-9]+:[a-zA-Z0-9]*",
		"^(true|false)",
		"^@[a-zA-Z]+",
		"^[.;,a\\[\\]()]"
	};
	i := 0;
	for (l := res; l != nil; l = tl l) {
		(re, e) = regex->compile(hd l, 0);
		re_list = (re, i++) :: re_list;
	}
	# reverse the list
	rl : list of (Re, int);
	for (ll := re_list; ll != nil; ll = tl ll)	
		rl = hd ll :: rl;
	re_list = rl;
}


advance(): string
{
	a: array of (int,int);

	if (tok == "(eof)") return "(eof)";
	line = str->drop(line, " \t\n");
	while (len line == 0){
		if ((line = io.gets('\n')) == nil) {
			tok = "(eof)";
			return tok;
		}
		linecount++;
		line = str->drop(line, " \t\n");
		if (len line > 0 && line[0] == '#')
			line = "";
	}

	for (l := re_list; l != nil; l = tl l){
		(re, typ) := hd l;
		a = regex->execute(re, line);
		if (a != nil) {
			(beg,end) := a[0];
			tok = line[beg:end];
			toktyp = typ;
			line = line[end:];
			if (len line > 0 && line[0] == '#')
				line = "";
			if(DEBUG)sys->print("\nadvance:%d %s\n", linecount, tok);
			return tok;
		}
	}
	error("advance() unrecognized token: " + tok + line);
	tok = "(eof)";
	return tok;
}


# Read an RDF turtle file and return a list of triples
read(f: string): list of ref Triple
{
	io = bufio->open(f, Bufio->OREAD);
	turtledoc();
	return triplestore;
}

# turtledoc ::= statement+
# statement ::= directive | triples '.'
# directive ::= prefix | base 
# prefix    ::= '@prefix' name iri '.'
# base      ::= '@base' iri '.'
# triples   ::= subject predicateObjectList | blankNodePropertyList predicateObjectList?
# predicateObjectList ::= verb objectList (';' (verb objectList)?)*
# objectList ::= object (',' object)*
# verb      ::= predicate | 'a'
# subject   ::= iri | blank | collection
# predicate ::= iri
# object    ::= iri | blank | literal | blankNodePropertyList | collection
# blankNodePropertyList ::= '[' predicateObjectList ']'
# collection  ::= '(' object* ')'
# literal   ::= string (LANG | '^^' iri) ?

eat(s: string)
{
	if (tok != s)
		error("unexpected tok: " + tok);
	advance();
}

nl()
{
	while (tok == "\n" || tok == ".")
		advance();
}

turtledoc()
{
	advance();
	while (tok != "(eof)")
		statement();
}

statement()
{
	if (tok == "@prefix"){
		prefix();
	}else if (tok == "@base") {
		base();
	}else {
		triples();
	}
}

prefix()
{
	eat("@prefix");
	nm := tok;
	if(toktyp != PNAME && toktyp != NAME) error("prefix: expecting name: " + tok);
	advance();
	p := tok;
	if(toktyp != IRI) error("prefix expecting iri");
	if(len nm == 1 && nm[0] == ':')
		emptyprefix = p[1:len p - 1];
	else
		prefixes = (nm, p[1:len p - 1]) :: prefixes;
	advance();
	nl();
}

base()
{
	eat("@base");
	if (tok[0] == '<')
		baseuri = tok[1:len tok -1];
	else
		error("unexpected base iri:" + tok);
	advance();
	nl();
}

triples()
{
	dprint("triples ");
	if (tok[0] == '[') {
		s := blankNodePropertyList();
		if (toktyp == IRI || toktyp == PNAME || 
			toktyp == NAME || tok[0] == 'a') {
			subject = s :: subject;
			predicateObjectList();
			subject = tl subject;
		}
	} else {
		subject = iri() :: subject;
		predicateObjectList();
		subject = tl subject;
	}
	nl();
}

predicateObjectList()
{
	dprint("predicateObjectList ");
	predicate = verb() :: predicate;
	objectList();
	predicate = tl predicate;
	while (tok[0] == ';'){
		eat(";");
		predicate = verb() :: predicate;
		objectList();
		predicate = tl predicate;
	}
}

objectList()
{
	dprint("objectList " + tok);
	triplestore = ref Triple(hd subject, hd predicate, object()) :: triplestore;
	while (tok[0] == ',') {
		eat(",");
		triplestore = ref Triple(hd subject, hd predicate, object()) :: triplestore;
	}
}

verb(): string
{
	dprint("verb " + tok);
	if (tok == "a") {
		eat("a");
		return "http://www.w3.org/1999/02/22-rdf-syntax-ns#type";
	} else {
		return predic();
	}
	return nil;
}

predic(): string
{
	dprint("predic " + tok);
	s := tok;

	if (s[0] == ':') 
		s = emptyprefix + s[1:];
	else if (s[0] == '<')
		s = s[1:len s - 1];
	else {
		(l, r) := str->splitr(s, ":");
		if(l == nil) error("predic: not an iri");
		pre := find(l);
		if(pre == nil) error("predic: " + l);
		s = pre + r;
	}
	advance();
	return s;
}

object(): string
{
	o: string;
	dprint("object " + tok);
	if (toktyp == QUOT) {
		o = tok;
		advance();
		if(toktyp == LANG)
			advance();
		return o;
	}
	if (toktyp == LDQ || toktyp == LSQ) {
		o = quotedString();
		advance();
		if(toktyp == LANG)
			advance();
		return o;
	}
	if(tok[0] == '(')
		return collection();
	if (toktyp == BLANK ||
		toktyp == IRI ||
		toktyp == NAME ||
		toktyp == PNAME)
		return iri();
	if (tok[0] == '[')
		return blankNodePropertyList();

	o = tok;
	advance();
	return o;
}

collection(): string
{
	l: list of string;
	eat("(");
	dprint("collection " + tok);
	while(tok != ")") {
		o := object();
		l = o :: l;
	}
	last: string;
	for (al := l; al != nil; al = tl al) {
		s := bpref + string blankcount++;
		triplestore = ref Triple(s, "rdf:first", hd al) :: triplestore;
		if(last != nil)
			triplestore = ref Triple(s, "rdf:rest", last) :: triplestore;
		else
			triplestore = ref Triple(s, "rdf:rest", "rdf:nil") :: triplestore;
		last = s;
	}
	if (last == nil) {
		s := bpref + string blankcount++;
		triplestore = ref Triple(s, "rdf:rest", "rdf:nil") :: triplestore;
		last = s;
	}
	eat(")");
	return last;
}

quotedString(): string
{
	s: string;

	if (len line > 0)
		s = line;
	line = "";
	while (len line == 0){
		if ((line = io.gets('\n')) == nil) {
			tok = "(eof)";
			return s;
		}
		linecount++;
		if (str->contains(line, tok)) {
			(l, r) := str->splitstrl(line, tok);
			s += l;
			line = r[3:];
			return s;
		} else {
			s += line;
			line = "";
		}
	}
	return s;
}

iri(): string
{
	s := tok;

	if (s[0] == ':') 
		s = emptyprefix + s[1:];
	else if (s[0] == '<'){
		s = s[1:len s - 1];
		if(!str->prefix("http", s)) {
			s = baseuri + s;
		}
	}else if (s[0] == '_')
		;
	else {
		(l, r) := str->splitr(s, ":");
		if(DEBUG)sys->print("iri: %s\n", tok);
		pre := find(l);
		if(pre == nil) error("iri: " + l + string toktyp);
		s = pre + r;
	}
	advance();
	return s;
}

blankNodePropertyList(): string
{
	dprint("blankNodePropertyList");
	s := bpref + string blankcount++;
	subject = s :: subject;
	eat("[");
	if(toktyp == IRI || toktyp == NAME || 
		toktyp == PNAME || tok[0] == 'a')
		predicateObjectList();
	eat("]");
	subject = tl subject;
	return s;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "Error line %d: %s\n",linecount, s);
	exit;
}

find(pre: string): string
{
	dprint("find ");
	for (l := prefixes; l != nil; l = tl l) {
		(p, s) := hd l;
		dprint(p + pre);
		if (p == pre)
			return s;
	}
	return nil;
}

dprint(s: string)
{
	if(DEBUG)sys->print("%s\n", s);
}