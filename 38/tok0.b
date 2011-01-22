implement Command;

include "sh.m";
include "sys.m";
	sys: Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;

Word: con 1;

wordval: string;
parse_eof: int;
bin, bout: ref Iobuf;
tok: int;
seq: int;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;

	bin = bufio->fopen(sys->fildes(0), Sys->OREAD);
	bout = bufio->fopen(sys->fildes(1), Sys->OWRITE);
	while(advance() != Bufio->EOF){
		if(tok == Word && wordval == "INSERT"){
			eat("INTO");
			advance();
			table := wordval;
			eat("VALUES");
			if(bout != nil)
				bout.close();
			bout = bufio->create(table + string seq++, Sys->OWRITE, 8r666);
			if(bout == nil){
				sys->fprint(sys->fildes(2), "error opening new file %s\n", table + string seq);
				exit;
			}
#			bout.puts("Insert " + table + "\n");
			rowlist();
		}
	}
	bout.close();
}

rowlist()
{
	for(;;){
		advance();
		case tok {
		'(' =>
			if(!row())
				return;
		',' =>
			advance();
			if(!row())
				return;
		';' =>
			return;
		}
	}
}

row(): int
{
	if(tok != '(')
		return 0;
	while(advance() != ')' && ! parse_eof) {
		if(tok == ',')
			continue;
		else if(tok == Word)
			bout.puts(sys->sprint("%q ", wordval));
	}
	bout.puts("\n");
	return 1;
}

eat(s: string)
{
	advance();
	if(parse_eof){
		sys->fprint(sys->fildes(2), "unexpected eof, expecting %s\n", s);
		exit;
	}
	if(tok != Word && wordval != s) {
		sys->fprint(sys->fildes(2), "parse error, expecting %s saw %s\n", s, wordval);
		exit;
	}
}

advance(): int
{
	tok = lex();
	return tok;
}

lex(): int
{
	c : int;
	if(parse_eof)
		return '\n';

# top:
	for(;;){
		c = getc();
		case c {
			Bufio->EOF =>
				return Bufio->EOF;
	 		' ' or '\t' or '\r' or '\n' =>
				break;
			'(' or ')' or '<' or '>' or '[' or ']' or '@' or '/' or ',' 
			or ';' or ':' or '?' or '=' =>
				return c;
	 		'`' =>
				word("`");
				getc();		# skip the closing quote 
				return Word;
	 		'\'' =>
				word("\'");
				getc();		# skip the closing quote 
				return Word;
	 		* =>
				ungetc();
				word("\"()<>@,;:/[]?=\r\n \t");
				return Word;
			}
	}
	return 0;	
}

word(stop : string)
{
	c : int;
	n := 0;
	while((c = getc()) != Bufio->EOF){
		if(c == '\r')
			c = wordcr();
		else if(c == '\n')
			c = wordnl();
		if(c == '\\'){
			c = getc();
			if(c == Bufio->EOF)
				break;
		}else if(str->in(c, stop)){
				ungetc();
				wordval = wordval[0:n];	
				return;
			}
#		if(c >= 'A' && c <= 'Z')
#			c += 'a' - 'A';
		wordval[n++] = c;
	}
	wordval = wordval[0:n];
	# sys->print("returning from word");
}


wordcr(): int
{
	c := getc();
	if(c == '\n')
		return wordnl();
	ungetc();
	return ' ';
}


wordnl(): int
{
	c := getc();
	if(c == ' ' || c == '\t')
		return c;
	ungetc();
	return '\n';
}


getc(): int
{
	c := bin.getc();
	if(c == Bufio->EOF){
		parse_eof = 1;
		return c;
	}
	return c;
}

ungetc() {
	# this is a dirty hack, I am tacitly assuming that characters read
	# from stdin will be ASCII.....
	bin.ungetc();
}
