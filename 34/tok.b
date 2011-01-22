implement Tok;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "hash.m";
	hash: Hash;
	HashTable: import hash;
include "string.m";
	str: String;
include "arg.m";
	arg: Arg;
include "cache.m";
include "btree.m";
include "names.m";
	names: Names;
include "workdir.m";
	workdir: Workdir;
include "lexis.m";
	lex: Lexis;
	Fact, Rule, Category, Relation, Attribute, Object: import lex;

stderr: ref Sys->FD;
stdin: ref Sys->FD;

Tok: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};
stopwords := array[] of {
    "a", "an", "and", "are", "as", "at", "be", "but", "by",
    "for", "if", "in", "into", "is", "it",
    "no", "not", "of", "on", "or", "s", "such",
    "t", "that", "the", "their", "then", "there", "these",
    "they", "this", "to", "was", "will", "with"
  };

nthread:int;
stop: ref HashTable;
lexicon: ref HashTable;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	hash = load Hash Hash->PATH;
	str = load String String->PATH;
	lex = load Lexis Lexis->PATH;
	names = load Names Names->PATH;
	workdir = load Workdir Workdir->PATH;
	arg = load Arg Arg->PATH;

	sys->pctl(Sys->NEWPGRP, nil);
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	arg->init(args);	
	index:="index.bt";
	nthread = 1;
	while((c := arg->opt()) != 0) {
		case c {
		'i' =>
			index = arg->earg();
		'p' =>
			nthread = int arg->earg();
		* =>
			sys->fprint(stderr, "%s: bad option %c\n", arg->progname(), c);
			usage(arg->progname());
		}
	}
	stop = hash->new(23);
	lexicon = hash->new(101);
	for(i:=0;i<len stopwords;i++)
		stop.insert(stopwords[i], 1 :: nil);
	args = arg->argv();
	cc := chan of int;
	spawn run(index, args, cc);
	pid := <-cc;
	<-cc;
	kill(pid);
}

kill(pid: int)
{
	path := sys->sprint("#p/%d/ctl", pid);
	fd := sys->open(path, sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}

Docid, Termid, Hit: int;

run(index: string, args: list of string, c: chan of int)
{
	c <-= sys->pctl(Sys->NEWPGRP, nil);
	lex->init(index);

	Docid = Rule.mk("Docid", Category).oid;
	Termid = Rule.mk("Termid", Category).oid;
	Hit = Rule.mk("Hit", Relation).oid;

	tokc := chan of string;
	for(i:=0; i<nthread;i++)
		spawn token(tokc);
	for(; args != nil; args = tl args){
		tokc <-= hd args;
	}
	for(i=0; i<nthread;i++)
		tokc <-= nil;
	lex->close();
	c <-=1;
	c <-=1;
}

token(c: chan of string)
{
	for(;;) alt{
	file := <-c =>
		if(file == nil)
			return;
		h := hash->new(23);
		filename := names->cleanname(names->rooted(workdir->init(), file));
		sys->print("adding %s\n", filename);
		docid := lex->getobjectid(filename, 1);
		(ref Fact.Category(docid, Docid)).put();
		io := bufio->open(filename, Sys->OREAD);
		pos := 0;
		while((s := io.gets('\n')) != nil){
			(nil, f) := sys->tokenize(s, "[]{}()!@#$%^&*?><\":;.,|\\-_~`'+=/ \t\n\r");
			for ( ; f != nil; f = tl f) {
				ss := str->tolower(hd f);
				if(stop.find(ss) == nil){
					h.insert(ss, pos :: h.find(ss));
					pos++;
				}
			}
		}
		for(l := h.all(); l != nil; l = tl l){
			wordid: int;
#			if((wl := lexicon.find((hd l).key)) == nil){
				wordid = lex->getobjectid((hd l).key, 0);
				if(wordid == 0){
					wordid = lex->getobjectid((hd l).key, 1);
					(ref Fact.Category(wordid, Termid)).put();
				}
#				lexicon.insert((hd l).key, wordid :: nil);
#			}else
#				wordid = hd wl;
#			p = pack((hd l).val);
#
#			n := sys->write(hitlist, p, len p);
			(ref Fact.Relation(docid, Hit, wordid)).put();
#			offset += n;
		}
	}
}

usage(s: string)
{
	sys->fprint(stderr, "usage: %s [-i index] file\n", s);
	exit;
}

pack(keys: list of int): array of byte
{
	buf := array[1024] of byte;
	n := 0;
	n = p32(buf, 0, len keys);
	for(; keys != nil; keys = tl keys){
		if(n >= len buf)
			buf = (array[len buf * 2] of byte)[0:] = buf;
		n = p32(buf, n, hd keys);
	}
	return buf[0:n];
}

p32(a: array of byte, o: int, v: int): int
{
	a[o] = byte v;
	a[o+1] = byte (v>>8);
	a[o+2] = byte (v>>16);
	a[o+3] = byte (v>>24);
	return o+4;
}
