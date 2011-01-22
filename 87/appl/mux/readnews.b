implement PAPER;

include "sys.m";
include "paper.m";

sys:	Sys;
open, read: import sys;

artlist: array of string;

scanpaper(s: string): (string, string, list of ref Article)
{
	al, rl: list of ref Article;
	a: ref Article;
	n, nb: int;
	date: string;

	sys = load Sys Sys->PATH;
	fd := open(s, sys->OREAD);
	if(fd == nil)
		return ("", sys->sprint("can't open paper file %s: %r\n", s), nil);
	buf := array[100000] of byte;
	nb = read(fd, buf, len buf);
	if(nb <= 0)
		return ("", sys->sprint("can't read paper file: %r\n"), nil);
	(n, date) = readline(buf, 0, nb);
	if(date==nil)
		return ("", sys->sprint("bad format paper file: bad date\n"), nil);
	(n, s) = readline(buf, n, nb);
	if(s != "#a")
		return ("", sys->sprint("bad format paper file: doesn't start with article\n"), nil);
	for(;;){
		(n, a) = readarticle(buf, n, nb);
		if(a == nil)
			break;
		al = a :: al;
	}
	# list is in reverse order; reverse again
	#  also, replace body (whole article) by index
	artlist = array[len al] of string;
	for (n=0; al!=nil; n++){
		artlist[n] = (hd al).bodynm;
		(hd al).bodynm = sys->sprint("%d", n);
		rl = hd al :: rl;
		al = tl al;
	}

	return (date, "", rl);
}

getarticle(a: string): string
{
	n := int a;
	if (n>=0 && n<len artlist)
		return artlist[n];
	return "";
}

readarticle(buf: array of byte, n, nb: int): (int, ref Article)
{
	title, body, s: string;
	video: string;

	(n, title) = readline(buf, n, nb);
	if(title == "")
		return (0, nil);
	video = nil;
	if(title[0:2] == "#v"){
		video = title[2:len title];
		(n, title) = readline(buf, n, nb);
		if(title == "")
			return (0, nil);
	}
	body = "";
	# skip leading blank lines
	while(n<nb && int buf[n]=='\n')
		n++;
	for(;;){
		(n, s) = readline(buf, n, nb);
		if(s=="#a" || n>=nb)
			break;
		if(len body>0 && body[len body-1]=='-')
			body = body[0:len body-1] + s;
		else
			body = body + " " + s;
	}
	return (n, ref Article(title, body, video));
}

readline(buf: array of byte, n, nb: int): (int, string)
{
	i: int;

	i = n;
	if(i<nb && int buf[i] == '\n')	# blank line
		return (i+1, "\n\n");
	while(i<nb && int buf[i]!='\n')
		i++;
	if(i < nb)
		return (i+1, string buf[n:i]);
	return (i, string buf[n:i]);
}
