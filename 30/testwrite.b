implement Testwrite;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "wiki.m";
	wiki: Wiki;

Testwrite: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;
	wiki = load Wiki Wiki->PATH;
	bufio = load Bufio Bufio->PATH;
	wiki->init(bufio);
	args = tl args;

	# read in a file
	# transform the string to a Wpage
	# make a Wdoc
	# convert back to a text string with sharps
	# write to the repository

	# sys->print("%d\n", wiki->nametonum(hd args));
	fd := wiki->wBopen(hd args, Sys->OREAD);
	w := wiki->Brdpage(fd, wiki->Srdwline);
	# wiki->printpage(w);
	s := wiki->pagetext("", w, 1);
	sys->print("%s", s);
}
