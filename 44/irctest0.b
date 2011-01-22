implement Irctest;

include "sys.m";
	sys: Sys;
	print, sprint, fprint, dup, fildes, pread, pctl, NEWPGRP,
	OREAD, OWRITE: import sys;
include "draw.m";
include "irc.m";
	irc: Irc;
	ircdial, login, ircjoin, Ichan, Imsg, Isub, irctolower, irccistrcmp,
	ircleave, nick, imsgfmt,
	readchan, writechan, subchan, unsubchan: import irc;
include "arg.m";
	arg: Arg;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
	str: String;

Irctest: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

chattyacme: int;
debug := 0;
nicks : list of string;
ircaddr: string;
server: string;
redial: int;
servername: string;
fullname: string;
passwd: string;
stderr: ref Sys->FD;
mainfd: ref Sys->FD;

Chat: adt {
	name: string;
	m: ref Imsg;
	ic: ref Ichan;
};

usage()
{
	fprint(fildes(2), "usage: airc [-r] [-f fullname] [-n nick] server\n");
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	pctl(NEWPGRP, nil);
	irc = load Irc Irc->PATH;
	irc->init();
	irccmd := "";

	str = load String String->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	for(l := args; l != nil; l = tl l){
		irccmd += hd l;
		if(tl args != nil)
			irccmd += " ";
	}
	arg->init(args);
	while((c := arg->opt()) != 0)
	case c {
	'A'  => chattyacme = 1;
	'D' => debug = 1;
	'V' => irc->chatty = 1;
	'f' => fullname = arg->earg();
	'n' => nicks = arg->earg() :: nicks;
	'r' => redial = 1;
	's' => servername = arg->earg();
	'p' => passwd = arg->earg();
	}
	args = arg->argv();
	if(len args != 1)
		usage();
	server = hd args;
	if(servername == nil)
		servername = server;

	pid := chan of int;
	spawn infothread(pid);
	<-pid;
	if(ircdial(server) < 0){
		fprint(stderr, "dial %s: %r", ircaddr);
		exit;
	}

	if(login(fullname, nicks, passwd) < 0){
		fprint(stderr, "login failed");
		exit;
	}
	name := "#inferno";
	(e, ic) := ircjoin(name, 0);
	if(e != nil) {
		fprint(fildes(2), "error joining channel %s\n", e);
		exit;
	}
	spawn chatwin(ic);
	inputrelay(name);
#	newchat("#inferno", nil);
}

inputrelay(name: string)
{
	b := bufio->fopen(fildes(0), Bufio->OREAD);
	while((p := b.gets('\n')) != nil){
		if(p[len p - 1] == '\n')
			p = p[:len p - 1];
		if(name != nil){
			buf := sprint("PRIVMSG %s :%s", name, p);
			writechan <-= buf;
		}else
			writechan <-= p;
	}
}

blankisub : Isub;

infomatch(nil: ref Isub, m: ref Imsg): int
{

	case m.cmdnum {
	332 or 333 or 353 or 366 or 252 or 315 =>
		return 0;
	* =>
		if(m.cmdnum > 0 && m.cmdnum < 400)
			return 1;
	}
	if(irccistrcmp(m.cmd, "NOTICE") == 0 && m.src == nil)
		return 1;
	if(irccistrcmp(m.cmd, "PART") == 0)
		return 1;
	if(irccistrcmp(m.cmd, "QUIT") == 0)
		return 1;
	if(irccistrcmp(m.cmd, "MODE") == 0)
		return 1;
	return 0;
}

infothread(c: chan of int)
{
	c <-= pctl(0, nil);
	sub := ref blankisub;
	sub.match = infomatch;
	sub.ml = chan[10] of ref Imsg;
	subchan <-= sub;

	while((m := <-sub.ml) != nil){
		buf := "";
		case m.cmdnum {
		* =>
			if(m.prefix != nil)
				buf = ":" + m.prefix;
			buf += m.cmd + " ";
			if(m.dst != nil)
				buf += m.dst + " ";
		1 or 2 or 3 or 4 or 5 
		or 250 or 251 or 252 or 254 
		or 255 or 265 or 372 or 375 
		or 376 =>
			;
		}
		for(l := m.arg; l != nil; l = tl l)
			if(tl l == nil)
				buf += hd l;
			else
				buf += hd l + " ";
		buf += "\n";
		print("infothread: %s", buf);	
	}
}

newchat(name: string, m: ref Imsg)
{
	(nil, ic) := ircjoin(name, m!=nil);
	if(ic == nil){
		fprint(fildes(2), "couldn't join channel %s\n", name);
		exit;
	}
	ch := ref Chat(name, m, ic);
 #	chatwin(ch);
}

chatwin(ic:ref Ichan)
{
	for(;;) alt {
	m := <- ic.chatter =>
		case m.cmdnum {
		Irc->RPL_NOTOPIC 
		or Irc->RPL_TOPIC 
		or Irc->RPL_OWNERTIME
		or Irc->RPL_LIST
		or Irc->ERR_NOCHANMODES =>
				;
		Irc->RPL_WHOISUSER 
		or Irc->RPL_WHOWASUSER =>
			print("<*> %s: %s@%s: %s\n", hd m.arg, hd tl m.arg, hd tl tl m.arg, hd tl tl tl m.arg);
		Irc->RPL_WHOISSERVER =>
			print("<*> %s: %s %s\n",
				hd m.arg, hd tl m.arg, hd tl tl m.arg);
		Irc->RPL_WHOISOPERATOR 
		or Irc->RPL_WHOISCHANNELS
		or Irc->RPL_WHOISIDENTIFIED =>
			print("<*> %s: %s\n",
				hd m.arg, hd tl m.arg);
		Irc->RPL_WHOISIDLE =>
			print("<*> %s: %s seconds idle\n",
				hd m.arg, hd tl m.arg);
		Irc->RPL_ENDOFWHO =>
			;
		* =>
			case lower(m.cmd) {
			"join" =>
				print("<*> Who +%s\n", m.src);
			"part" =>
				print("<*> Who -%s\n", m.src);
			"quit" =>
				print("<*> Who -%s (%s)\n", 
					m.src, m.dst);
			"nick" =>
				print("<*> Who %s => %s\n",
					m.src, m.dst);
			"privmsg" =>
				print("<%s> %s\n", m.src, hd m.arg);
			"notice" =>
				print("[%s] %s\n", m.src, hd m.arg);
			"ping" =>
				;
			* =>
				print("unexpected msg: %s\n", imsgfmt(m));
			}
		}
	}
#	ircleave(ic);
}

lower(s: string): string
{
	t: string;
	for(i := 0; i< len s; i++)
		t[i] = irctolower(s[i]);
	return t;
}
