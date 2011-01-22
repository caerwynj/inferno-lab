implement Man2html;

include "draw.m";
include "sys.m";
include "bufio.m";
include "parseman.m";
	parser: Parseman;
	FONT_ROMAN, FONT_BOLD, FONT_ITALIC: import parser;

Man2html : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);

	# Viewman signature...
	textwidth : fn (text : Parseman->Text) : int;

};

sys : Sys;
bufio : Bufio;
Iobuf : import bufio;
output : ref Iobuf;

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if (bufio == nil) {
		sys->print("cannot load Bufio module: %r\n");
		raise "fail:init";
	}

	stdout := sys->fildes(1);
	output = bufio->fopen(stdout, Sys->OWRITE);

	parser = load Parseman "/dis/parseman.dis";
	parser->init();

	argv = tl argv;
	for (; argv != nil ; argv = tl argv) {
		fname := hd argv;
		fd := sys->open(fname, Sys->OREAD);
		if (fd == nil) {
			sys->print("cannot open %s: %r\n", fname);
			continue;
		}
		vm := load Viewman SELF;
		m := Parseman->Metrics(55, 1, 1, 1, 1, 5, 2);
		
		datachan := chan of list of (int, Parseman->Text);
		spawn parser->parseman(fd, m, 1, vm, datachan);
		output.puts("<pre>");
		for (;;) {
			line := <- datachan;
			if (line == nil)
				break;
			setline(line);
		}
		output.flush();
		output.puts("</pre>");
	}
	output.close();
}

textwidth(text : Parseman->Text) : int
{
	return len text.text;
}

inpara := 0;
prevailindent := 0;
setline(line : list of (int, Parseman->Text))
{
	offset := 0;
	str : string;
	for (; line != nil; line = tl line) {
		(indent, txt) := hd line;
		str = txt.text;

		while (offset < indent) {
			output.putc(' ');
			offset++;
		}
		case txt.font {
		FONT_ITALIC => str = "<i>" + str + "</i>";
		FONT_BOLD => str = "<b>" + str + "</b>";
		};
		case txt.heading {
		1 =>
			str = "<b>" + str + "</b>";
		2 =>
			str = "<b>" + str + "</b>";
		};
		if(txt.link != nil && txt.text[0] == '(')
			str = "<a href=\"http://www.vitanuova.com/inferno/man/" + txt.link + ".html\">" + str + "</a>";
		else if(txt.link != nil && txt.link[0:4] == "http")
			str = "<a href=\"" + txt.link + "\">" + str + "</a>";
		output.puts(str);
		offset += len txt.text;
	}
	output.putc('\n');
}
