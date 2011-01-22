implement Testwrite;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "wiki.m";
	wiki: Wiki;
	Whist, Wdoc, Wpage: import wiki;
include "string.m";
	str: String;

Testwrite: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;
	wiki = load Wiki Wiki->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	wiki->init(bufio);
	args = tl args;

	newfile(hd args);
}

newfile(file: string)
{
	w: ref Whist;
	t, n: int;
	title, author, comment: string;

	fd := wiki->wBopen(file, Sys->OREAD);
	if((title = fd.gets('\n')) == nil)
		return;
	w = ref Whist;
	w.title = str->tolower(title[0:len title-1]);
	author = "me";
	t = 0;
	while((s := fd.gets('\n')) != nil && s != "\n"){
		case s[0] {
		'A' =>
			author = s[1:len s - 1];
		'D' =>
			t = int s[1:];
		'C' =>
			comment = s[1: len s - 1];
		}
	}
	w.doc = array[1] of ref Wdoc;
	w.doc[0] = ref Wdoc(author, comment, 0, t, nil);
	
	w.doc[0].wtxt = wiki->Brdpage(fd, wiki->Srdwline);
	w.ndoc = 1;
	n = wiki->allocnum(w.title, 0);
	s = wiki->doctext(w.doc[0]);
	wiki->writepage(n, t, s, w.title);
}
