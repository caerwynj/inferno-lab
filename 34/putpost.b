implement Putpost;

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
	btreem: Btreem;
	Btree: import btreem;
include "names.m";
	names: Names;
include "workdir.m";
	workdir: Workdir;
include "lexis.m";
	lex: Lexis;
	Fact, Rule, Category, Relation, Attribute, Object: import lex;

bt: ref Btree;
stderr: ref Sys->FD;
stdin: ref Sys->FD;

Putpost: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

nthread:int;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	hash = load Hash Hash->PATH;
	str = load String String->PATH;
	lex = load Lexis Lexis->PATH;
	btreem = load Btreem Btreem->PATH;
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

User, Url, Title, Comment, Tag, Post:int;

run(index: string, args: list of string, c: chan of int)
{
	c <-= sys->pctl(Sys->NEWPGRP, nil);
	lex->init(index);

	# define the rules
	User = Rule.mk("User", Relation).oid;
	Url = Rule.mk("Url", Relation).oid;
	Title = Rule.mk("Title", Attribute).oid;
	Comment = Rule.mk("Comment", Attribute).oid;
	Post = Rule.mk("Post", Category).oid;

	tokc := chan of string;
	for(i := 0; i<nthread;i++)
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
		filename := names->cleanname(names->rooted(workdir->init(), file));
		sys->print("adding %s\n", filename);
		postid := lex->mkobjectid();
		(ref Fact.Category(postid, Post)).put();
		io := bufio->open(filename, Sys->OREAD);
		while((s := io.gets('\n')) != nil){
			(q, r) := str->splitl(s, "= \t\n\r");
			r = str->take(str->drop(r, "= \t"), "^\r\n");
			case q {
			"user" =>
				userid := lex->getobjectid(r, 1);
				fact := ref Fact.Relation(postid, User, userid);
				fact.put();
			"url" =>
				urlid := lex->getobjectid(r, 1);
				fact := ref Fact.Relation(postid, Url, urlid);
				fact.put();
			"title" =>
				fact := ref Fact.Attribute(postid, Title, array of byte r);
				fact.put();
			}
		}
	}
}

usage(s: string)
{
	sys->fprint(stderr, "usage: %s [-i index] file\n", s);
	exit;
}

