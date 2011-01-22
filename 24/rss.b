implement Rss;

include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "xml.m";
	xml: Xml;
	Parser, Item, Locator, Attributes, Mark: import xml;

iob: ref Iobuf;

Rss: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	xml = load Xml Xml->PATH;

	argv = tl argv;
	stderr := sys->fildes(2);
	xml->init();
		(p, e) := xml->open(hd argv, nil, nil);
		if(p == nil){
			sys->fprint(stderr, "error %s", e);
			exit;
		}
		traverse(p);
}

lastag: string;

prtag(i: ref Item)
{

	pick x := i {
	Tag =>
		if(x.name == "title")
			sys->print("\n");
		if(x.name == "link")
			lastag = "plumb";
		else
			lastag = x.name + ":";
	Text =>
		if(len x.ch != 0)
			sys->print("%s %s\n", lastag, x.ch);
	Process =>
	Doctype =>
	Stylesheet =>
	Error =>
		sys->print("Error %s\n", x.msg);
	}
}

traverse(p: ref Parser)
{
	i := p.next();
	if(i == nil)
		return;
	#action on i
	prtag(i);
	p.down();
	traverse(p);
	p.up();
	traverse(p);
}
