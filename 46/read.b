implement Tmpl0;
include "sys.m";
	sys: Sys;
	print, sprint, fprint, fildes, write, Connection: import sys;
include "draw.m";
include "venti.m";
	venti: Venti;
	Session, Score: import venti;

Tmpl0: module {init: fn(nil: ref Draw->Context, argv: list of string);};


S: ref Session;

error(s: string)
{
	fprint(fildes(2), "%s %r", s);
	exit;
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	venti = load Venti Venti->PATH;
	venti->init();
	
	argv = tl argv;
	if(argv == nil)
		error("usage: read score");
	(sn, score) := Score.parse(hd argv);
	if(sn == -1)
		error("error parsing score");
	(n, conn) := sys->dial("tcp!oak!5555", nil);
	if(n < 0)
		error("dial error");
	S = Session.new(conn.dfd);
	if(S == nil)
		error("Session error");
	fprint(fildes(2), "session started\n");
	n=-1;
	buf: array of byte;
	for(typ:=0; typ<venti->Maxtype; typ++){
		buf = S.read(score, typ, venti->Maxlumpsize);
		if(buf != nil){
			fprint(fildes(2), "venti/read %s %d\n", score.text(), typ);
			break;
		}
	}
	if(buf == nil)
		error("could not read block");
	if(write(fildes(1), buf, len buf) != len buf)
		error("write: ");
}
