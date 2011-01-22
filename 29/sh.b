implement WmSh;

include "sys.m";
	sys: Sys;
	FileIO: import sys;

include "draw.m";
	draw: Draw;
	Context, Rect: import draw;

include "tk.m";
	tk: Tk;

include "tkclient.m";
	tkclient: Tkclient;

include	"plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg: import plumbmsg;

include "workdir.m";

include "string.m";
	str: String;

include "arg.m";
# for brutus extensions
include "bufio.m";
	bufio: Bufio;
include "brutus.m";
include "brutusext.m";
	imgext: Brutusext;

WmSh: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
};

Command: type WmSh;

BSW:		con 23;		# ^w bacspace word
BSL:		con 21;		# ^u backspace line
EOT:		con 4;		# ^d end of file
ESC:		con 27;		# hold mode

# XXX line-based limits are inadequate - memory is still
# blown if a client writes a very long line.
HIWAT:	con 2000;	# maximum number of lines in transcript
LOWAT:	con 1500;	# amount to reduce to after high water

Name:	con "Shell";

Rdreq: adt
{
	off:	int;
	nbytes:	int;
	fid:	int;
	rc:	chan of (array of byte, string);
};

shwin_cfg := array[] of {
	"menu .m",
	".m add command -text noscroll -command {send edit noscroll}",
	".m add command -text cut -command {send edit cut}",
	".m add command -text paste -command {send edit paste}",
	".m add command -text snarf -command {send edit snarf}",
	".m add command -text send -command {send edit send}",
	"frame .b -bd 1 -relief ridge",
	"frame .ft -bd 0",
	"scrollbar .ft.scroll -command {send scroll t}",
	"text .ft.t -bd 1 -relief flat -yscrollcommand {send scroll s} -bg white -selectforeground black -selectbackground #CCCCCC",
	".ft.t tag configure sel -relief flat",
	"pack .ft.scroll -side left -fill y",
	"pack .ft.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .b -anchor w -fill x",
	"pack .ft -fill both -expand 1",
	"focus .ft.t",
	"bind .ft.t <Key> {send keys {%A}}",
	"bind .ft.t <Control-d> {send keys {%A}}",
	"bind .ft.t <Control-h> {send keys {%A}}",
	"bind .ft.t <Control-w> {send keys {%A}}",
	"bind .ft.t <Control-u> {send keys {%A}}",
	"bind .ft.t <Button-1> +{send but1 pressed}",
	"bind .ft.t <Double-Button-1> +{send but1 pressed}",
	"bind .ft.t <ButtonRelease-1> +{send but1 released}",
	"bind .ft.t <ButtonPress-2> {send but2 %X %Y}",
	"bind .ft.t <Motion-Button-2-Button-1> {}",
	"bind .ft.t <Motion-ButtonPress-2> {}",
	"bind .ft.t <ButtonPress-3> {send but3 pressed}",
	"bind .ft.t <ButtonRelease-3> {send but3 released %x %y}",
	"bind .ft.t <Motion-Button-3> {}",
	"bind .ft.t <Motion-Button-3-Button-1> {}",
	"bind .ft.t <Double-Button-3> {}",
	"bind .ft.t <Double-ButtonRelease-3> {}",
};

rdreq: list of Rdreq;
menuindex := "0";
holding := 0;
plumbed := 0;
rawon := 0;
rawinput := "";
scrolling := 1;
partialread: array of byte;
cwd := "";
width, height, font: string;
history := array[1024] of byte;
nhistory := 0;

events: list of string;
evrdreq: list of Rdreq;
winname: string;

badmod(p: string)
{
	sys->print("wm/sh: cannot load %s: %r\n", p);
	raise "fail:bad module";
}

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	# for brutus
	imgext = load Brutusext "/dis/wm/brutus/image.dis";
	bufio = load Bufio Bufio->PATH;

	tkclient = load Tkclient Tkclient->PATH;
	if (tkclient == nil)
		badmod(Tkclient->PATH);

	str = load String String->PATH;
	if (str == nil)
		badmod(String->PATH);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	arg->init(argv);

	plumbmsg = load Plumbmsg Plumbmsg->PATH;

	sys->pctl(Sys->FORKNS | Sys->NEWPGRP | Sys->FORKENV, nil);

	tkclient->init();
	if (ctxt == nil)
		ctxt = tkclient->makedrawcontext();
	if(ctxt == nil){
		sys->fprint(sys->fildes(2), "sh: no window context\n");
		raise "fail:bad context";
	}

	if(plumbmsg != nil && plumbmsg->init(1, nil, 0) >= 0){
		plumbed = 1;
		workdir := load Workdir Workdir->PATH;
		cwd = workdir->init();
	}

	shargs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'w' =>
			width = arg->arg();
		'h' =>
			height = arg->arg();
		'f' =>
			font = arg->arg();
		'c' =>
			a := arg->arg();
			if (a == nil) {
				sys->print("usage: wm/sh [-ilxvn] [-w width] [-h height] [-f font] [-c command] [file [args...]\n");
				raise "fail:usage";
			}
			shargs = a :: "-c" :: shargs;
		'i' or 'l' or 'x' or 'v' or 'n' =>
			shargs = sys->sprint("-%c", opt) :: shargs;
		}
	}
	argv = arg->argv();
	for (; shargs != nil; shargs = tl shargs)
		argv = hd shargs :: argv;

	winname = Name + " " + cwd;

	spawn main(ctxt, argv);
}

task(t: ref Tk->Toplevel)
{
	tkclient->wmctl(t, "task");
}

atend(t: ref Tk->Toplevel, w: string): int
{
	s := cmd(t, w+" yview");
	for(i := 0; i < len s; i++)
		if(s[i] == ' ')
			break;
	return i == len s - 2 && s[i+1] == '1';
}

main(ctxt: ref Draw->Context, argv: list of string)
{
	(t, titlectl) := tkclient->toplevel(ctxt, "", winname, Tkclient->Appl);
	wm := t.ctxt;

	edit := chan of string;
	tk->namechan(t, edit, "edit");

	keys := chan of string;
	tk->namechan(t, keys, "keys");

	butcmd := chan of string;
	tk->namechan(t, butcmd, "button");

	event := chan of string;
	tk->namechan(t, event, "action");

	scroll := chan of string;
	tk->namechan(t, scroll, "scroll");

	but1 := chan of string;
	tk->namechan(t, but1, "but1");
	but2 := chan of string;
	tk->namechan(t, but2, "but2");
	but3 := chan of string;
	tk->namechan(t, but3, "but3");
	button1 := 0;
	button3 := 0;

	for (i := 0; i < len shwin_cfg; i++)
		cmd(t, shwin_cfg[i]);
	(menuw, nil) := itemsize(t, ".m");
	if (font != nil) {
		if (font[0] != '/' && (len font == 1 || font[0:2] != "./"))
			font = "/fonts/" + font;
		cmd(t, ".ft.t configure -font " + font);
	}
	cmd(t, ".ft.t configure -width 65w -height 20h");
	cmd(t, "pack propagate . 0");
	if(width != nil)
		cmd(t, ". configure -width " + width);
	if(height != nil)
		cmd(t, ". configure -height " + height);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "ptr" :: "kbd" :: nil);

	ioc := chan of (int, ref FileIO, ref FileIO, string, ref FileIO, ref FileIO);
	spawn newsh(ctxt, ioc, argv);

	(nil, file, filectl, consfile, shctl, hist) := <-ioc;
	if(file == nil || filectl == nil || shctl == nil) {
		sys->print("newsh: shell cons creation failed\n");
		return;
	}
	dummyfwrite := chan of (int, array of byte, int, Sys->Rwrite);
	fwrite := file.write;

	rdrpc: Rdreq;

	# outpoint is place in text to insert characters printed by programs
	cmd(t, ".ft.t mark set outpoint 1.0; .ft.t mark gravity outpoint left");

	for(;;) alt {
	c := <-wm.kbd =>
		tk->keyboard(t, c);
	m := <-wm.ptr =>
		tk->pointer(t, *m);
	c := <-wm.ctl or
	c = <-t.wreq or
	c = <-titlectl =>
		tkclient->wmctl(t, c);
	ecmd := <-edit =>
		editor(t, ecmd);
		sendinput(t);

	c := <-keys =>
		cut(t, 1);
		char := c[1];
		if(char == '\\')
			char = c[2];
		if(rawon) {
			rawinput[len rawinput] = char;
			rawinput = sendraw(rawinput);
			break;
		}
		case char {
		* =>
			cmd(t, ".ft.t insert insert "+c);
		'\n' or EOT =>
			cmd(t, ".ft.t insert insert "+c);
			sendinput(t);
		'\b' =>
			cmd(t, ".ft.t tkTextDelIns -c");
		BSL =>
			cmd(t, ".ft.t tkTextDelIns -l");
		BSW =>
			cmd(t, ".ft.t tkTextDelIns -w");
		ESC =>
			holding ^= 1;
			color := "blue";
			if(!holding){
				color = "black";
				tkclient->settitle(t, winname);
				sendinput(t);
			}else
				tkclient->settitle(t, winname+" (holding)");
			cmd(t, ".ft.t configure -foreground "+color);
		}
		cmd(t, ".ft.t see insert;update");

	c := <-but1 =>
		button1 = (c == "pressed");
		button3 = 0;	# abort any pending button 3 action

	c := <-but2 =>
		if(button1){
			cut(t, 1);
			cmd(t, "update");
			break;
		}
		(nil, l) := sys->tokenize(c, " ");
		x := int hd l - menuw/2;
		y := int hd tl l - int cmd(t, ".m yposition "+menuindex) - 10;
		cmd(t, ".m activate "+menuindex+"; .m post "+string x+" "+string y+
			"; update");
		button3 = 0;	# abort any pending button 3 action

	c := <-but3 =>
		if(c == "pressed"){
			button3 = 1;
			if(button1){
				paste(t);
				cmd(t, "update");
			}
			break;
		}
		if(plumbed == 0 || button3 == 0 || button1 != 0)
			break;
		button3 = 0;
		# plumb message triggered by release of button 3
		(nil, l) := sys->tokenize(c, " ");
		x := int hd tl l;
		y := int hd tl tl l;
		index := cmd(t, ".ft.t index @"+string x+","+string y);
		selindex := cmd(t, ".ft.t tag ranges sel");
		if(selindex != "")
			insel := cmd(t, ".ft.t compare sel.first <= "+index)=="1" &&
				cmd(t, ".ft.t compare sel.last >= "+index)=="1";
		else
			insel = 0;
		attr := "";
		if(insel)
			text := tk->cmd(t, ".ft.t get sel.first sel.last");
		else{
			# have line with text in it
			# now extract whitespace-bounded string around click
			(nil, w) := sys->tokenize(index, ".");
			charno := int hd tl w;
			left := cmd(t, ".ft.t index {"+index+" linestart}");
			right := cmd(t, ".ft.t index {"+index+" lineend}");
			line := tk->cmd(t, ".ft.t get "+left+" "+right);
			for(i=charno; i>0; --i)
				if(line[i-1]==' ' || line[i-1]=='\t')
					break;
			for(j:=charno; j<len line; j++)
				if(line[j]==' ' || line[j]=='\t')
					break;
			text = line[i:j];
			attr = "click="+string (charno-i);
		}
		msg := ref Msg(
			"WmSh",
			"",
			cwd,
			"text",
			attr,
			array of byte text);
		if(msg.send() < 0)
			sys->fprint(sys->fildes(2), "sh: plumbing write error: %r\n");
	c := <-butcmd =>
		simulatetype(t, tkunquote(c));
		sendinput(t);
		cmd(t, "update");
	c := <-event =>
		events = str->append(tkunquote(c), events);
		if (evrdreq != nil) {
			rc := (hd evrdreq).rc;
			rc <-= (array of byte hd events, nil);
			evrdreq = tl evrdreq;
			events = tl events;
		}
	rdrpc = <-shctl.read =>
		if(rdrpc.rc == nil)
			continue;
		if (events != nil) {
			rdrpc.rc <-= (array of byte hd events, nil);
			events = tl events;
		} else
			evrdreq = rdrpc :: evrdreq;
	(nil, data, nil, wc) := <-shctl.write =>
		if (wc == nil)
			break;
		if ((err := shctlcmd(t, string data)) != nil)
			wc <-= (0, err);
		else
			wc <-= (len data, nil);
	(off, nbytes, nil, rc) := <-hist.read =>
		if (rc == nil)
			break;
		if (off > nhistory)
			off = nhistory;
		if (off + nbytes > nhistory)
			nbytes = nhistory - off;
		rc <-= (history[off:off + nbytes], nil);
	(nil, data, nil, wc) := <-hist.write =>
		if (wc != nil)
			wc <-= (0, "cannot write");
	rdrpc = <-filectl.read =>
		if(rdrpc.rc == nil)
			continue;
		rdrpc.rc <-= (nil, "not allowed");
	(nil, data, nil, wc) := <-filectl.write =>
		if(wc == nil) {
			# consctl closed - revert to cooked mode
			# XXX should revert only on *last* close?
			rawon = 0;
			continue;
		}
		(nc, cmdlst) := sys->tokenize(string data, " \n");
		if(nc == 1) {
			case hd cmdlst {
			"rawon" =>
				rawon = 1;
				rawinput = "";
				# discard previous input
				advance := string (len tk->cmd(t, ".ft.t get outpoint end") +1);
				cmd(t, ".ft.t mark set outpoint outpoint+" + advance + "chars");
				partialread = nil;
			"rawoff" =>
				rawon = 0;
				partialread = nil;
			* =>
				wc <-= (0, "unknown consctl request");
				continue;
			}
			wc <-= (len data, nil);
			continue;
		}
		wc <-= (0, "unknown consctl request");

	rdrpc = <-file.read =>
		if(rdrpc.rc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		append(rdrpc);
		sendinput(t);

	c := <-scroll =>
		if(c[0] == 't'){
			cmd(t, ".ft.t yview "+c[1:]+";update");
			if(scrolling)
				fwrite = file.write;
			else if(atend(t, ".ft.t"))
				fwrite = file.write;
			else
				fwrite = dummyfwrite;
		}else{
			cmd(t, ".ft.scroll set "+c[1:]+";update");
			if(atend(t, ".ft.t") && fwrite == dummyfwrite)
				fwrite = file.write;
		}
	(off, data, fid, wc) := <-fwrite =>
		if(wc == nil) {
			(ok, nil) := sys->stat(consfile);
			if (ok < 0)
				return;
			continue;
		}
		needscroll := atend(t, ".ft.t");
		cdata := cursorcontrol(t, string data);
		ncdata := string len cdata + "chars;";
		moveins := insat(t, "outpoint");
		cmd(t, ".ft.t insert outpoint '"+ cdata);
		wc <-= (len data, nil);
		data = nil;
		s := ".ft.t mark set outpoint outpoint+" + ncdata;
		if(!atend(t, ".ft.t") && scrolling == 0)
			fwrite = dummyfwrite;
		else if(needscroll)
			s += ".ft.t see outpoint;";
		if(moveins)
			s += ".ft.t mark set insert insert+" + ncdata;
		s += "update";
		cmd(t, s);
		nlines := int cmd(t, ".ft.t index end");
		if(nlines > HIWAT){
			s = ".ft.t delete 1.0 "+ string (nlines-LOWAT) +".0;update";
			cmd(t, s);
		}
	}
}

tkunquote(s: string): string
{
	if (s == nil)
		return nil;
	t: string;
	if (s[0] != '{' || s[len s - 1] != '}')
		return s;
	for (i := 1; i < len s - 1; i++) {
		if (s[i] == '\\')
			i++;
		t[len t] = s[i];
	}
	return t;
}

buttonid := 0;
bitmapid := 0;
shctlcmd(win: ref Tk->Toplevel, c: string): string
{
	toks := str->unquoted(c);
	if (toks == nil)
		return "null command";
	n := len toks;
	case hd toks {
	"bitmap" =>
		if (n != 2)
			return "bad usage";
		id := ".ext" + string bitmapid++;
		imgext->init(sys, draw, bufio, tk, tkclient);
		err := imgext->create(cwd, win, id, hd tl toks);
		if(err != ""){
			return err;
		}
		cmd(win, ".ft.t window create outpoint -window " +  id);
		cmd(win, ".ft.t mark set outpoint outpoint+1");
	"graph" =>
		if (n != 2)
			return "bad usage";
		id := ".ext" + string bitmapid++;
		graph := load Brutusext "/usr/caerwyn/lab/29/graph.dis";
		graph->init(sys, draw, bufio, tk, tkclient);
		err := graph->create(cwd, win, id, hd tl toks);
		if(err != ""){
			return err;
		}
		cmd(win, ".ft.t window create outpoint -window " +  id);
		cmd(win, ".ft.t mark set outpoint outpoint+1");
	"button" or
	"action"=>
		# (button|action) title sendtext
		if (n != 3)
			return "bad usage";
		id := ".b.b" + string buttonid++;
		cmd(win, "button " + id + " -text " + tk->quote(hd tl toks) +
				" -command 'send " + hd toks + " " + tk->quote(hd tl tl toks));
		cmd(win, "pack " + id + " -side left");
		cmd(win, "pack propagate .b 0");
	"clear" =>
		for (i := 0; i < buttonid; i++)
			cmd(win, "destroy .b.b" + string i);
		buttonid = 0;
		buttonid = 0;
		for (i = 0; i < bitmapid; i++)
			cmd(win, "destroy .ext" + string i);
		bitmapid = 0;
	"cwd" =>
		if (n != 2)
			return "bad usage";
		cwd = hd tl toks;
		winname = Name + " " + cwd;
		tkclient->settitle(win, winname);
	* =>
		return "bad command";
	}
	cmd(win, "update");
	return nil;
}


RPCread: type (int, int, int, chan of (array of byte, string));

append(r: RPCread)
{
	t := r :: nil;
	while(rdreq != nil) {
		t = hd rdreq :: t;
		rdreq = tl rdreq;
	}
	rdreq = t;
}

insat(t: ref Tk->Toplevel, mark: string): int
{
	return cmd(t, ".ft.t compare insert == "+mark) == "1";
}

insininput(t: ref Tk->Toplevel): int
{
	if(cmd(t, ".ft.t compare insert >= outpoint") != "1")
		return 0;
	return cmd(t, ".ft.t compare {insert linestart} == {outpoint linestart}") == "1";
}

isalnum(s: string): int
{
	if(s == "")
		return 0;
	c := s[0];
	if('a' <= c && c <= 'z')
		return 1;
	if('A' <= c && c <= 'Z')
		return 1;
	if('0' <= c && c <= '9')
		return 1;
	if(c == '_')
		return 1;
	if(c > 16rA0)
		return 1;
	return 0;
}

cursorcontrol(t: ref Tk->Toplevel, s: string): string
{
	l := len s;
	for(i := 0; i < l; i++) {
		case s[i] {
		    '\b' =>
			pre := "";
			rem := "";
			if(i + 1 < l)
				rem = s[i+1:];
			if(i == 0) {	# erase existing character in line
				if(tk->cmd(t, ".ft.t get " +
					"{outpoint linestart} outpoint") != "")
				    cmd(t, ".ft.t delete outpoint-1char");
			} else {
				if(s[i-1] != '\n')	# don't erase newlines
					i--;
				if(i)
					pre = s[:i];
			}
			s = pre + rem;
			l = len s;
			i = len pre - 1;
		    '\r' =>
			s[i] = '\n';
			if(i + 1 < l && s[i+1] == '\n')	# \r\n
				s = s[:i] + s[i+1:];
			else if(i > 0 && s[i-1] == '\n')	# \n\r
				s = s[:i-1] + s[i:];
			l = len s;
		    '\0' =>
			s[i] = Sys->UTFerror;
		}
	}
	return s;
}

editor(t: ref Tk->Toplevel, ecmd: string)
{
	s, snarf: string;

	case ecmd {
	"scroll" =>
		menuindex = "0";
		scrolling = 1;
		cmd(t, ".m entryconfigure 0 -text noscroll -command {send edit noscroll}");
	"noscroll" =>
		menuindex = "1";
		scrolling = 0;
		cmd(t, ".m entryconfigure 0 -text scroll -command {send edit scroll}");
	"cut" =>
		menuindex = "1";
		cut(t, 1);
	"paste" =>
		menuindex = "2";
		paste(t);
	"snarf" =>
		menuindex = "3";
		if(cmd(t, ".ft.t tag ranges sel") == "")
			break;
		snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
		tkclient->snarfput(snarf);
	"send" =>
		menuindex = "4";
		if(cmd(t, ".ft.t tag ranges sel") != ""){
			snarf = tk->cmd(t, ".ft.t get sel.first sel.last");
			tkclient->snarfput(snarf);
		}else{
			snarf = tkclient->snarfget();
		}
		if(snarf != "")
			s = snarf;
		else
			return;
		if(s[len s-1] != '\n' && s[len s-1] != EOT)
			s[len s] = '\n';
		simulatetype(t, s);
	}
	cmd(t, "update");
}

simulatetype(t: ref Tk->Toplevel, s: string)
{
	appendhist(s);
	cmd(t, ".ft.t see end; .ft.t insert end '"+s);
	cmd(t, ".ft.t mark set insert end");
	tk->cmd(t, ".ft.t tag remove sel sel.first sel.last");
}

cut(t: ref Tk->Toplevel, snarfit: int)
{
	if(cmd(t, ".ft.t tag ranges sel") == "")
		return;
	if(snarfit)
		tkclient->snarfput(tk->cmd(t, ".ft.t get sel.first sel.last"));
	cmd(t, ".ft.t delete sel.first sel.last");
}

paste(t: ref Tk->Toplevel)
{
	snarf := tkclient->snarfget();
	if(snarf == "")
		return;
	cut(t, 0);
	cmd(t, ".ft.t insert insert '"+snarf);
	cmd(t, ".ft.t tag add sel insert-"+string len snarf+"chars insert");
	sendinput(t);
}

sendinput(t: ref Tk->Toplevel)
{
	if(holding || rdreq == nil)
		return;
	input := tk->cmd(t, ".ft.t get outpoint end");
	if(input == nil)
		return;
	r := hd rdreq;
	(chars, bytes, partial) := triminput(r.nbytes, input, partialread, 0);
	if(chars == nil)
		return;	# no terminator yet
	rdreq = tl rdreq;

	alt {
	r.rc <-= (bytes, nil) =>
		# check that it really was sent
		alt {
		r.rc <-= (nil, nil) =>
			cmd(t, ".ft.t mark set outpoint outpoint+" + string len chars + "chars");
			appendhist(chars);
			partialread = partial;
			return;
		* =>
			;
		}
	* =>
		# requester has disappeared; ignore his request and try another
		;
	}
	sendinput(t);
}

sendraw(input : string): string
{
	if(rdreq == nil)
		return input;

	r := hd rdreq;
	rdreq = tl rdreq;

	(chars, bytes, partial) := triminput(r.nbytes, input, partialread, 1);

	alt {
	r.rc <-= (bytes, nil) =>
		# check that it really was sent
		alt {
		r.rc <-= (nil, nil) =>
			input = input[len chars:];
			partialread = partial;
		* =>
			;
		}
	* =>
		;	# requester has disappeared; ignore his request and try another
	}
	return input;
}

#
# read at most nr bytes from the input string, returning the result as both
# characters and as the bytes for full and partial characters within that count
#
triminput(nr: int, input: string, partial: array of byte, raw: int): (string, array of byte, array of byte)
{
	slen := len input;
	if(nr > slen*Sys->UTFmax)
		nr = slen*Sys->UTFmax;		# keep the array bounds within sensible limits
	a := array[nr+Sys->UTFmax] of byte;
	i := 0;
	if(partial != nil){
		a[0:] = partial;
		i = len partial;
		partial = nil;
	}
	nc := 0;
	while(i < nr) {
		if(nc >= len input){
			if(!raw)
				return (nil, nil, nil);	# no terminator yet
			break;
		}
		c := input[nc++];
		if(!raw && c == EOT)
			break;
		i += sys->char2byte(c, a, i);
		if(!raw && c == '\n')
			break;
	}
	if(i > nr){
		partial = a[nr:i];
		i = nr;
	}
	return (input[0:nc], a[0:i], partial);
}

appendhist(s: string)
{
	d := array of byte s;
	if (len d + nhistory > len history) {
		newhistory := array[(len d + nhistory) * 3 / 2] of byte;
		newhistory[0:] = history[0:nhistory];
		history = newhistory;
	}
	history[nhistory:] = d;
	nhistory += len d;
}

newsh(ctxt: ref Context, ioc: chan of (int, ref FileIO, ref FileIO, string, ref FileIO, ref FileIO),
			args: list of string)
{
	pid := sys->pctl(sys->NEWFD, nil);

	sh := load Command "/dis/sh.dis";
	if(sh == nil) {
		ioc <-= (0, nil, nil, nil, nil, nil);
		return;
	}

	tty := "cons."+string pid;

	sys->bind("#s","/chan",sys->MBEFORE);
	fio := sys->file2chan("/chan", tty);
	fioctl := sys->file2chan("/chan", tty + "ctl");
	shctl := sys->file2chan("/chan", "shctl");
	hist := sys->file2chan("/chan", "history");
	ioc <-= (pid, fio, fioctl, "/chan/"+tty, shctl, hist);
	if(fio == nil || fioctl == nil || shctl == nil)
		return;

	sys->bind("/chan/"+tty, "/dev/cons", sys->MREPL);
	sys->bind("/chan/"+tty+"ctl", "/dev/consctl", sys->MREPL);

	fd0 := sys->open("/dev/cons", sys->OREAD|sys->ORCLOSE);
	fd1 := sys->open("/dev/cons", sys->OWRITE);
	fd2 := sys->open("/dev/cons", sys->OWRITE);

	{
		sh->init(ctxt, "sh" :: "-n" :: args);
	}exception{
	"fail:*" =>
		exit;
	}
}

cmd(top: ref Tk->Toplevel, c: string): string
{
	s:= tk->cmd(top, c);
#	sys->print("* %s\n", c);
	if (s != nil && s[0] == '!')
		sys->fprint(sys->fildes(2), "wmsh: tk error on '%s': %s\n", c, s);
	return s;
}

itemsize(top: ref Tk->Toplevel, item: string): (int, int)
{
	w := int tk->cmd(top, item + " cget -actwidth");
	h := int tk->cmd(top, item + " cget -actheight");
	b := int tk->cmd(top, item + " cget -borderwidth");
	return (w+b, h+b);
}
