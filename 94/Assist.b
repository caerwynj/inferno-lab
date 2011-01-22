implement Assist;

include "sys.m";
	sys: Sys;
	open, print, sprint, fprint, dup, fildes, pread, pctl, read, write,
	OREAD, OWRITE: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "acmewin.m";
	win: Acmewin;
	Win, Event: import win;
include "string.m";
	stringm: String;
include "sh.m";
	sh: Sh;
include "env.m";
	env: Env;
include "complete.m";
	complete: Complete;
include "workdir.m";
	workdir: Workdir;
include "names.m";
	names: Names;

Assist: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

# Content-Assist for Acme
# Run Assist [filename] in an editor window to assist just that window.
# The default [filename] is /lib/words used to find completions
# While in the editor window:
# 	Type Ctrl-l to step through completions in the assist window.
# 	Type Ctrl-k to choose a completion.
# 	Type Ctrl-y to see file completions.

stderr: ref Sys->FD;
mainevent : chan of string;
maincmd : chan of string;
BUFSIZE: con  4096;
lineno := 1;
nlines := 0;
mwin: ref Win;
awin: ref Win;
lookfile: string;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	win = load Acmewin Acmewin->PATH;
	win->init();
	stringm = load String String->PATH;
	stderr = fildes(2);
	bufio = load Bufio Bufio->PATH;
	env = load Env Env->PATH;
	complete = load Complete Complete->PATH;
	complete->init();
	workdir = load Workdir Workdir->PATH;
	names = load Names Names->PATH;
	
	sys->pctl(Sys->NEWPGRP, nil);
	mainevent = chan of string;
	maincmd = chan of string;
	winid := "";
	args = tl args;
	winid = env->getenv("acmewin");
	if(len args == 1)
		lookfile = hd args;
	awin = wnew(winid);
	spawn assistwin(awin);
	mwin = Win.wnew();
	mwin.wname("+Assist");
	mwin.wclean();
	mwin.wselect("$");
	spawn mainwin(mwin);
}

wnew(id: string): ref Win
{
	w := ref Win;
	w.winid = int id;
	w.ctl = w.openfile("ctl");
	w.event = w.openfile("event");
	w.addr = nil;	# will be opened when needed
	w.body = nil;
	w.data = nil;
	w.bufp = w.nbuf = 0;
	w.buf = array[512] of byte;
	return w;
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

doexec(nil: ref Win, cmd: string): int
{
	cmd = skip(cmd, "");
	arg: string;
	(cmd, arg) = stringm->splitl(cmd, " \t\r\n");
	if(arg != nil)
		arg = skip(arg, "");
	case cmd {
	"Del" or "Delete" =>
		return -1;
	* =>
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

assistwin(w: ref Win)
{
	c := chan of Event;
	na: int;
	ea: Event;
	s: string;

	spawn w.wslave(c);
	for(;;){
		e := <- c;
		if(e.c1 == 'K' && (e.c2 == 'I')){
			q0 := e.q0;
			q1 := e.q1;
			ss := string e.b[0:e.nb];
			ch := ss[0];
			if(ch == ''){   # ctrl-l   look down the list
				w.wreplace(sprint("#%d,#%d", q0, q1), "");
				if(nlines > 0){
					lineno++;
					if(lineno > nlines)
						lineno = 1;
					mwin.wselect(string lineno);
					mwin.wshow();
				}
				continue;
			}else if(ch == ''){  # ctrl-k select the completion
				sel := rdsel(mwin);
				if(sel[len sel - 1] == '\n')
					sel = sel[:len sel - 1];
				q0--;
				while(q0 >= 0){
					sss := w.wread(q0, q0+1);
					ch = sss[0];
					 if(!isalnum(ch))
					 	break;
					q0--;
				}
				if(q0 < 0)
					q0 = 0;
				else if(q0 >= 0)
					q0++;
				w.wreplace(sprint("#%d,#%d", q0, q1), sel);
				continue;
			}else if(ch == ''){  # ctrl-y show file completions
				w.wreplace(sprint("#%d,#%d", q0, q1), "");
				mwin.wreplace("0,$", "");
				f := filecomplete(w, q0);
				if(f != nil){
					w.wreplace(sprint("#%d,#%d", q0, q0), f);
					continue;
				}
				lineno = 1;
				mwin.wselect(string lineno);
				continue;
			}
			while(q0 >= 0 && isalnum(ch)){
				sss := w.wread(q0, q0+1);
				ch = sss[0];
				q0--;
			}
			if(q0 < 0 && isalnum(ch))
				q0 = 0;
			else
				q0 += 2;
			ss = w.wread(q0, q1);
#			sys->print("%s\n", ss);
			mainevent <-= ss;
		}
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
			w.wwriteevent(ref e);
		'l' or 'L' =>
			w.wwriteevent(ref e);
		}
	}
	postnote(1, pctl(0, nil), "kill");
	w.wdel(1);
	exit;
}

mainwin(w: ref Win)
{
	c := chan of Event;
	na: int;
	ea: Event;
	s: string;

	spawn w.wslave(c);
	loop: for(;;) alt{
		ss := <- mainevent =>
			if(len ss <= 1)
				; #w.wwritebody(ss + "\n");
			else
				dispmatches(w, ss);
		e := <- c =>
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
				w.wwriteevent(ref e);
		}
	}
	postnote(1, pctl(0, nil), "kill");
	w.wdel(1);
	exit;
}

dispmatches(cwin: ref Win, s: string)
{
	lineno = 1;
	buf := array[BUFSIZE] of byte;
	args : list of string;
	if(lookfile != nil)
		args = "/dis/look.dis" :: "-f" :: s :: lookfile :: nil;
	else
		args = "/dis/look.dis" :: "-f" :: s :: nil;
	fd := procrexec(args);
	cwin.wreplace("0,$", "");
	nlines = 0;
	while((nb := read(fd, buf, BUFSIZE)) > 0) {
		ss := string buf[0:nb];
		for(i := 0; i < len ss; i++)
			if(ss[i] == '\n')
				nlines++;
		cwin.wwritebody(ss);
	}
	if(nlines > 0)
		cwin.wselect(string lineno);
}

procrexec(xprog: list of string): ref Sys->FD
{
	p := array[2] of ref Sys->FD;

	if(sys->pipe(p) < 0)
		return nil;
	sync := chan of int;
#	xprog  = "/dis/sh" :: "-n" :: "-c" :: l2s(xprog) :: nil;
	spawn exec(sync, hd xprog, xprog, (array[2] of ref Sys->FD)[0:] = p);
	<-sync;
	p[1] = nil;
	return p[0];
}

l2s(l: list of string): string
{
	s := "";
	for(; l != nil; l = tl l)
		s += " " + hd l;
#	print("%s\n", s);
	return  s;
}

exec(sync: chan of int, cmd : string, argl : list of string, out: array of ref Sys->FD)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	sys->pctl(Sys->FORKFD, nil);
	sys->dup(out[1].fd, 1);
	out[0] = nil;
	out[1] = nil;
	sync <-= sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);
	c := load Command file;
	if(c == nil) {
		err := sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sprint("%r");
		}
		if(c == nil){
			# debug(sprint("file %s not found\n", file));
			sys->fprint(sys->fildes(2), "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(nil, argl);
}

isalnum(c : int) : int
{
	#
	# Hard to get absolutely right.  Use what we know about ASCII
	# and assume anything above the Latin control characters is
	# potentially an alphanumeric.
	#
	if(c <= ' ')
		return 0;
	if(16r7F<=c && c<=16rA0)
		return 0;
	if(strchr("!\"#$%&'()*+,-./:;<=>?@[\\]^`{|}~", c) >= 0)
		return 0;
	return 1;
	# return ('a' <= c && c <= 'z') || 
	#	   ('A' <= c && c <= 'Z') ||
	#	   ('0' <= c && c <= '9');
}

strchr(s : string, c : int) : int
{
	for (i := 0; i < len s; i++)
		if (s[i] == c)
			return i;
	return -1;
} 

rdsel(w: ref Win): string
{
	s, t : string;
	rd := bufio->open(sprint("/chan/%d/rdsel", w.winid), OREAD);
	if(rd ==  nil)
		return "";
	s = nil;
	while ((t = rd.gets('\n')) != nil)
		s += t;
	rd.close();
	return s;
}

filecomplete(w: ref Win, q0: int): string
{

	nstr := filewidth(w, q0, 1);
	npath := filewidth(w, q0-nstr, 0);
	
	nlines = 0;
	q := q0-nstr;
	str := "";
	path := "";
	for(i:=0; i<nstr; i++){
		str[i] = w.wread(q, q+1)[0];
		q++;
	}
	q = q0-nstr-npath;
	for(i=0; i<npath; i++){
		path[i] = w.wread(q, q+1)[0];
		q++;
	}
	if(npath>0 && path[0]=='/')
		dir:=path;
	else{
		dir = workdir->init();
		if(len dir == 0)
			dir = ".";
		dir = dir + "/" + path;
		dir = names->cleanname(dir);
	}
	c := complete->complete(dir, str);
	if(c == nil){
		warning(nil, sprint("error attempting complete: %r\n"));
		return nil;
	}
	if(!c.advance){
		if(len dir > 0 && dir[len dir - 1] != '/')
			s := "/";
		else
			s = "";
		
		if(c.nmatch)
			match := "";
		else
			match = ": no matches in:";
			
		warning(nil, sprint("%s%s%s*%s\n",dir, s, str, match));
		for(i=0; i<c.nfile; i++)
			warning(nil, sprint("%s\n", c.filename[i]));
	}

	if(c.advance)
		return c.str;
	else
		return nil;
	
	return nil;
}

filewidth(w: ref Win, q0, oneelement: int): int
{
	q: int;
	r: int;
	
	q = q0;
	while(q > 0){
		s := w.wread(q-1, q);
		r = s[0];
		if(r <= ' ')
			break;
		if(oneelement && r == '/')
			break;
		--q;
	}
	return q0-q;
}

warning(nil: string, s: string)
{
	mwin.wwritebody(s);
	nlines++;
}
