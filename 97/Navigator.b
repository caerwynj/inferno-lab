implement Navigator;

include "sys.m";
	sys: Sys;
	open, print, sprint, fprint, dup, fildes, pread, pctl, read, write,
	OREAD, OWRITE: import sys;
include "draw.m";
include "bufio.m";
include "acmewin.m";
	win: Acmewin;
	Win, Event: import win;
include "string.m";
	str: String;
include "readdir.m";
	readdir: Readdir;
include "names.m";
	names: Names;
include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

Navigator: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

stderr: ref Sys->FD;
cwd: string;
plumbed := 0;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	win = load Acmewin Acmewin->PATH;
	win->init();
	str = load String String->PATH;
	stderr = fildes(2);
	readdir = load Readdir Readdir->PATH;
	names = load Names Names->PATH;
	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	if(plumbmsg->init(1, nil, 0) >= 0){
		plumbed = 1;
	}
	
	args = tl args;
	if (len args != 0)
		cwd = names->cleanname(hd args);
	else
		cwd = "/";
	w := Win.wnew();
	w.wname("/+Navigator");
	w.wtagwrite("Get Pin");
	w.wclean();
	dolook(w, cwd);
	spawn mainwin(w);
}

postnote(t : int, pid : int, note : string) : int
{
	fd := open("#p/" + string pid + "/ctl", OWRITE);
	if (fd == nil)
		return -1;
	if (t == 1)
		note += "grp";
	fprint(fd, "%s", note);
	fd = nil;
	return 0;
}

doexec(w: ref Win, cmd: string): int
{
	cmd = skip(cmd, "");
	arg: string;
	(cmd, arg) = str->splitl(cmd, " \t\r\n");
	if(arg != nil)
		arg = skip(arg, "");
	case cmd {
	"Del" or "Delete" =>
		return -1;
	"Pin" =>
		if(plumbed){
			msg := ref Msg("Navigator", "", 
			cwd, "text", "click=1",
			array of byte sprint("%s", cwd));
			if(msg.send() < 0)
				fprint(sys->fildes(2), "Navigator: plumbing write error: %r\n");
		}
		return 1;
	"Get" =>
		return dolook(w, ".");
	* =>
		return 0;
	}
	return 1;
}

dolook(w: ref Win, file: string): int
{
	file = names->cleanname(names->rooted(cwd, file));
	fd := sys->open(file, Sys->OREAD);
	if(fd == nil){
		sys->fprint(stderr, "can't open %s: %r\n", file);
		return 1;
	}
	(nil, d) := sys->fstat(fd);
	if(d.qid.qtype & Sys->QTDIR){
		cwd = file;
		(a, n) := readdir->readall(fd, Readdir->NAME);
		if(file == "/")
			w.wname(file + "+Navigator");
		else
			w.wname(file + "/+Navigator");
		w.wreplace(",", "");
		w.wwritebody("..\n");
		for(i := 0; i < n; i++){
			s := "";
			if(a[i].qid.qtype & Sys->QTDIR)
				s = "/";
			w.wwritebody(sprint("%s%s\n", a[i].name, s));
		}
		w.ctlwrite("dump Navigator " + cwd + "\n");
		w.wclean();
	}else{
		return 0;
	}
	return 1;
}

skip(s, cmd: string): string
{
	s = s[len cmd:];
	while(s != nil && (s[0] == ' ' || s[0] == '\t' || s[0] == '\n'))
		s = s[1:];
	return s;
}

mainwin(w: ref Win)
{
	c := chan of Event;
	na: int;
	ea: Event;
	s: string;

	spawn w.wslave(c);
	loop: for(;;){
		e := <- c;
		if(e.c1 != 'M')
			continue;
		case e.c2 {
		'x' or 'X' =>
			eq := e;
			if(e.flag & 2)
				eq =<- c;
			if(e.flag & 8){
				ea =<- c; 
				na = ea.nb;
				<- c; #toss
			}else
				na = 0;

			if(eq.q1>eq.q0 && eq.nb==0)
				s = w.wread(eq.q0, eq.q1);
			else
				s = string eq.b[0:eq.nb];
			if(na)
				s +=  " " + string ea.b[0:ea.nb];
			#sys->print("exec: %s\n", s);
			n := doexec(w, s);
			if(n == 0)
				w.wwriteevent(ref e);
			else if(n < 0)
				break loop;
		'l' or 'L' =>
			eq := e;
			if(e.flag & 2)
				eq =<-c;
			s = string eq.b[0:eq.nb];
			if(eq.q1>eq.q0 && eq.nb==0)
				s = w.wread(eq.q0, eq.q1);
			n := dolook(w, s);
			if(n == 0)
				w.wwriteevent(ref e);
		}
	}
	postnote(1, pctl(0, nil), "kill");
	w.wdel(1);
	exit;
}
