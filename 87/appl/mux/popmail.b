#
# FILE:		popmail.b
#
# CONTAINS:	Prefab user interface for POP3 mail program (mail read only)
#		Sending canned messages using SMTP protocol
#

implement Command;

include "sys.m";
sys: Sys;
FD, Connection: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

# include the POP3 email io interface.
include "emio.m";
emio : EMIO;

# include the SMTP interface
include "smtp.m";
smtp : Smtp;

include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

# Globals
zr: Rect;
stderr: ref FD;
screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
tenv: ref Environ;
ones: ref Image;
replyList : array of string; 	# reply strings for all messages
subjList : array of string; 	# subject strings for all messages
hdrs : array of string;		# List of headers

Main:	 con 0;
Message: con 1;
DOT:	 con 46;

init(ctxt: ref Context, argv: list of string)
{
	key: int;
	se: ref Element;

	cs: Command;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;
	if ((sys == nil) || (draw == nil) || (prefab == nil))
		sys->print ("Module loads failed. Die\n");

	stderr = sys->fildes(2);
	# Start IP Network Services.
        sys->bind ("#I", "/net", sys->MAFTER);
        sys->bind ("#C", "/", sys->MAFTER);

	# Load the cs.
        cs = load Command "/dis/lib/cs.dis";
        if(cs == nil) {
                sys->fprint (stderr, "cs module load failed: %r\n");
		return;
	}
        else
                cs->init (nil, nil);
 
        # Load the email io module.
        emio = load EMIO "/dis/mux/emio.dis";
        if (emio == nil) {
                sys->fprint (stderr, "Failed to load emio\n");
                return;
        }

	# Load the smtp module
	smtp = load Smtp Smtp->PATH;
	if (smtp == nil) {
		sys->fprint (stderr, "Failed to load smtp\n");
		return;
	}

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;
	
	zr = ((0, 0), (0, 0));
	ones = display.color(draw->White);
	textfont := Font.open(display, "*default*");
	if (textfont == nil) {
		sys->fprint (stderr, "Failed to load *default* font\n");
		return;
	}

	style := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			# display.rgb(161, 195, 209),	# screencolor
			display.color(130),		# elemcolor; light blue
			display.color(draw->Black),	# edgecolor
			display.color(draw->Yellow),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.rgb(255, 255, 180-32));	# highlightcolor

	env = ref Environ(ctxt.screen, style);

	tstyle := ref Style(
			textfont,			# titlefont
			textfont,			# textfont
			# display.rgb(161, 195, 209),	# screencolor
			display.color(draw->White),	# elemcolor
			display.color(draw->Black),	# edgecolor
			display.color(draw->Black),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.rgb(255, 255, 180-32));	# highlightcolor

	tenv = ref Environ(ctxt.screen, tstyle);

	# Initialize the email io module
        emio->init();
	# Initialize the smtp module
	# smtp->init();

	# Get the mail server machine.
	if (len argv < 3) {
		sys->fprint (stderr, "Not enough arguments supplied\n");
		return;
	}
	argv1 := hd (tl argv);
        server := "tcp!" + string argv1 + "!110";
        smtpserver := "tcp!" + string argv1 + "!25";
 
        # Get the user name and password.
        # Read the username
	argv2 := hd (tl (tl argv));
        username := argv2;
 
        # read the password.
        msg : string;
        success : int;
	slavectl := chan of int;
	pw := getpasswd (ctxt, "");
	if (pw == -1) {
                ctxt.ctomux <-= Mux->AMexit;
		return;
	}
	else 
		password := string pw;
 
        # Open the mail box for the specified user/password.
        (success, msg) = emio->open(server, username, password);
        if (!success) {
#                sys->fprint(stderr, "emio->open failed: %s\n", msg);
		msg = string msg[0:len msg];
                errnotify (ctxt, "Mail Program", "   Error:  " + msg + "  ");
                ctxt.ctomux <-= Mux->AMexit;
                return;
        }
	# Open the smtp connection
	(success, msg) = smtp->open(smtpserver);
	if (!success) {
#		sys->fprint(stderr, "smtp->open failed: %s\n", msg);
		msg = string msg[0:len msg];
		errnotify (ctxt, "Mail Program", "   Error:  " + msg + "  ");
		ctxt.ctomux <-= Mux->AMexit;
		return;
	}
 
        # Read in all mail headers
	hdrs = readmsgs (ctxt, username);

	ctxt.ctomux <-= Mux->AMstartir;
	spawn topslave(ctxt.ctoappl, slavectl);

	if(hdrs == nil) {
		slavectl <-= Mux->AMexit;
		ctxt.ctomux <-= Mux->AMexit;
		return;
	}

	envelope := display.open("/icons/envelope.bit");
	if(envelope == nil) {
		sys->fprint(stderr, "can't open envelope.bit: %r\n");
		ctxt.ctomux <-= Mux->AMexit;
		return;
	}

	et := Element.text(env, "E-Mail", zr, Prefab->EText);
	e := Element.elist(env, nil, Prefab->EVertical);
	hdrsLength := len hdrs;
	for(i := 0; i < hdrsLength; i++) {
		ee := Element.elist(env, nil, Prefab->EHorizontal);
		ee.append(Element.icon(env, envelope.r, envelope, ones));
		ee.append(Element.text(env, hdrs[i], zr, Prefab->EText));
		ee.adjust(Prefab->Adjpack, Prefab->Adjleft);
		e.append(ee);
	}
	e.adjust(Prefab->Adjpack, Prefab->Adjup);
	e.clip(Rect((0, 0), (600, 400)));
	c := Compound.box(env, Point(10, 10), et, e);
	c.draw();

	windows[Main] = c.image;

	n := 0;
	i = len hdrs;
	for(;;) {
		(key, n, se) = c.select(c.contents, n, ctxt.cir);
		case key {
		Ir->Select =>
			view(ctxt, n+1, hdrs[n], username);
			# Redraw the headers list if message was deleted
			if (hdrsLength > len hdrs) {
			    hdrsLength = len hdrs;
			    e = nil;
			    e = Element.elist(env, nil, Prefab->EVertical);
			    for(hx := 0; hx < hdrsLength; hx++) {
                		ee := Element.elist(env, nil, 
						Prefab->EHorizontal);
                		ee.append(Element.icon(env, envelope.r, 
						envelope, ones));
                		ee.append(Element.text(env, hdrs[hx], zr, 
						Prefab->EText));
                		ee.adjust(Prefab->Adjpack, Prefab->Adjleft);
                		e.append(ee);
        		    }
        		    e.adjust(Prefab->Adjpack, Prefab->Adjup);
        		    e.clip(Rect((0, 0), (600, 400)));
        		    lc := Compound.box(env, Point(10, 10), et, e);
        		    lc.draw();
			}
		Ir->Enter =>
			slavectl <-= Mux->AMexit;
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
		n++;
		if(n >= i)
			n = 0;
	}
}

#
# FUNCTION:	view()
#
# PURPOSE:	view one message
#
#
view (ctxt: ref Context, mailno: int, title, username: string)
{
	key, n: int;
	se: ref Element;
	a: array of string;
	canned: string;

	ci := ctxt.cir;

	# read the specified messsage
	strtext, errmsg : string;
	success : int;
	(success, errmsg, strtext) = emio->msgtextstring(mailno);
        if (!success) {
	    sys->fprint(stderr, 
		"popmail:view()-emio->msgtexstring() failed: %s\n", errmsg);
       	    return;
        }
	if (strtext[len strtext-3] == DOT)
		strtext = string strtext[0:len strtext-3];

	msg := Compound.textbox(tenv, ((10, 54), (610, 400)), title, strtext);
	msg.draw();
	windows[Message] = msg.image;

	menu := array[] of {
		"Continue",
		"Delete",
		"Reply",
		"Save",
		"Forward",
		"Canned mail" };

	me := Element.elist(env, nil, Prefab->EHorizontal);
	for(i := 0; i < len menu; i++)
		me.append(Element.text(env, menu[i], zr, Prefab->EText));

	me.adjust(Prefab->Adjequal, Prefab->Adjcenter);
	me.clip(((0, 0), (600, 20)));

	et := Element.text(env, "Command", zr, Prefab->EText);
	mc := Compound.box(env, Point(10, 10), et, me);
	mc.draw();

	height := tenv.style.textfont.height;
	nlines := msg.contents.r.dy()/height;
	maxlines := len msg.contents.kids;
	dlines := 0;
	if(nlines != maxlines)
		dlines = 2*nlines/3;
	firstline := 0;

	for(;;) {
		(key, n, se) = mc.select(mc.contents, 0, ci);
		case key {
		Ir->Up =>
			if(dlines>0 && firstline>0) {
				msg.contents.scroll((0, dlines*height));
				msg.draw();
				firstline -= dlines;
			}
		Ir->Dn =>
			if(dlines>0 && firstline+nlines<maxlines) {
				msg.contents.scroll((0, -dlines*height));
				msg.draw();
				firstline += dlines;
			}
		Ir->Select =>
			p := se.r.min;
			case n {
			0 => # Continue
				windows[Message] = nil;
				return;
			1 => # Delete
				(ret, emsg) := emio->deletemessage(mailno);
				if (ret <= 0) {
				    sys->fprint(stderr,
			     "emio->deletemessage(%d) failed: %s\n", 
						mailno, emsg);
				}    
				hdrs = delHdr(mailno, hdrs);
				windows[Message] = nil;
				return;
			2 => # Reply
				(ret, emsg) := smtp->sendmail (
					username,
					replyList[mailno-1] :: nil,
					"Re:  "+subjList[mailno-1] :: nil,
					canned :: nil);
				if (ret <= 0) {
					sys->fprint (stderr,
				"smtp->sendmail() failed: %s\n", emsg);
					return;
				}
			3 => # Save
				a = readfile("folders");
				if(a == nil)
					break;
				key = choose(a, "Choose Folder ", p, ci);
				if(key >= 0) {
					#sys->fprint(io, "s %s\n", a[key]);
				}
			4 => # Forward
				a = readfile("forward");
				if(a == nil)
					break;
				key = choose(a, "Choose Address", p, ci);
				if(key >= 0) {
					#sys->fprint(io, "m %s\n", a[key]);
				}
			5 => # Canned mail;
				a = readfile ("canned_mail");
				if (a == nil)
					break;
				key = choose(a,"Choose Canned Message",p,ci);
				if (key >= 0) {
					# save selection fo use
					canned = a[key];
				}
			}
		Ir->Enter =>
			windows[Message] = nil;
			return;
		}
	}
}

choose(a: array of string, title: string, p: Point, ci: chan of int) : int
{
	me := Element.elist(env, nil, Prefab->EVertical);
	for(i := 0; i < len a; i++)
		me.append(Element.text(env, a[i], zr, Prefab->EText));

	me.adjust(Prefab->Adjequal, Prefab->Adjcenter);

	et := Element.text(env, title, zr, Prefab->EText);
	mc := Compound.box(env, p, et, me);
	mc.draw();

	(key, n, se) := mc.select(mc.contents, 0, ci);
	case key {
	Ir->Select =>
		return n;
	* =>
		return -1;
	}
}

readfile(name: string) : array of string
{
	fd := sys->open("/services/email/"+name, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	(v, l) := sys->tokenize(string buf[0:n], "\n");
	a := array[v] of string;
	for(i := 0; l != nil; l = tl l)
		a[i++] = hd l;

	return a;
}


readmsgs(ctxt: ref Context, username: string) : array of string
{
 
        totalmsg, success : int;
        msg : string;
 
        # Get the total number of messages
        (totalmsg, msg) = emio->numberofmessages();
        if (totalmsg == -1) {
                sys->fprint(stderr, "email->numberofmessages() failed: %s\n", msg);
                return nil;
        }
        else if (totalmsg == 0) {
           	errnotify(ctxt, "Mail Program", "   No mail for " + username);
                return nil;
        }
 
        # Size the arrays (hdrs, replyList are global)
        hdrs = array[totalmsg] of string;
        allmsgs := array[totalmsg] of string;
        replyList = array[totalmsg] of string;
        subjList = array[totalmsg] of string;
 
        # Read all messages in just saving the headers
        strtext : string;
	msgoctets : int;
        for (i := 1; i <= totalmsg; i++)
        {
                (success, msg, strtext) = emio->msgtextstring(i);
                if (!success) {
                        sys->fprint(stderr, "%s\n", msg);
                        continue;
                }
		# get length of the message
		(success, msg) = emio->messagelength(i);
                if (success == -1) {
                        sys->fprint(stderr, 
				"emio->messagelength(%d) failed: %s\n", i, msg);
                        continue;
                }
		else
			msgoctets = success;
                allmsgs[i-1] = strtext;
                (n, oneMsgList) := sys->tokenize (strtext, "\n");
                from, date, subject : string;
                for (; oneMsgList != nil; oneMsgList = tl oneMsgList) {
                        s := hd oneMsgList;
                        # Collect the header
                        if (len s >= 3) {
                                if (string s[0:3] == "Ret") {
                                        retpath := string s[13:len s];
				}
                                if (string s[0:3] == "Fro") {
                                        from = string s[6:len s];
					(sink, rf) := sys->tokenize(from,"(");
					replyList[i-1] = hd rf;
				}
                                if (string s[0:3] == "Dat")
                                        date = string s[6:len s];
                                if (string s[0:3] == "Sub") {
                                        subject = string s[9:len s];
					subjList[i-1] = subject;
				}
                        }
                }
                hdrs[i-1] = string i + "\t" + string msgoctets + "\t" + from + "\n" + date + "\t" + subject;
        }
        return hdrs;

}

topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for(;;) {
		alt{
		m = <-ctoappl =>
			if(m == Mux->MAtop)
				screen.top(windows);
		m = <-ctl =>
			return;
		}
	}
}

#
# FUNCTION:	getpasswd()
# 
# PURPOSE:	prompts the user for a 4-digit passwd
#
#
getpasswd(ctxt: ref Context, msg: string) : int
{
        i,n: int;
        key: int;
        r: Rect;
	se: ref Element;
        ldisp := ctxt.display;
 
        ones = ldisp.color(draw->White);
        textfont := Font.open(ldisp, "/fonts/lucida/unicode.20.font");
	if (textfont == nil) {
		sys->fprint(stderr,"Failed to open lucida/unicode.20.font\n");
		textfont = Font.open(ldisp, "*default*");
	}
 
        style := ref Style(
                        textfont,                       # titlefont
                        textfont,                       # textfont
                        # ldisp.rgb(161, 195, 209),     # screencolor
                        ldisp.color(draw->Red),       # elemcolor
                        ldisp.color(draw->Black),     # edgecolor
                        ldisp.color(draw->Yellow),    # titlecolor
                        ldisp.color(draw->White),     # textcolor
                        ldisp.color(130));            # highlightcolor
 
        lenv := ref Environ(ctxt.screen, style);
 
        pin := array[] of {"_", "_", "_", "_"};
        inpin := array[] of {"_", "_", "_", "_"};
        n = 0;
        for(;;){
                r = ((0,0),(0,0));
                et := Element.elist(lenv, nil, Prefab->EVertical);
     et.append(Element.text(lenv, " Enter a 4 digit password ", r, Prefab->ETitle));
       et.append(Element.text(lenv, " to access your mailbox ", r, Prefab->ETitle));
		if (msg != nil)
                	et.append(Element.text(lenv, msg, r, Prefab->ETitle));
                et.adjust(Prefab->Adjequal, Prefab->Adjcenter);
                e := Element.elist(lenv, nil, Prefab->EHorizontal);
                r = ((0,0),(textfont.width("m"), textfont.height));
                for(i = 0; i < 4; i++)
                        e.append(Element.text(lenv, pin[i], r, Prefab->EText));
 
                e.adjust(Prefab->Adjequal, Prefab->Adjcenter);
 
                c := Compound.box(lenv, Point(150, 150), et, e);
                c.draw();
 
                ctxt.ctomux <-= Mux->AMstartir;
 
out:            for(;;) {
                        (key, n, se) = c.select(c.contents, n, ctxt.cir);
                        case key {
                        Ir->Select =>
                                n = 0;
                                for(i = 0; i < 4; i++){
                                        if(pin[i] == "?" || pin[i] == "_"){
				errnotify(ctxt, "Bad Password",
					  "   password must be 4 digits");
                                                n = i;
                                                break out;
                                        }
                                        n = n*10 + int inpin[i];
                                }
                                return n;
                        Ir->Enter =>
                                return -1;
                        Ir->Up =>
                                n--;
                                if(n < 0)
                                        n = 3;
                        Ir->Dn =>
                                n++;
                                if(n >= 4)
                                        n = 0;
                        0 to 9 =>
                                inpin[n] = string key;
				pin[n] = string "*";
                                n++;
                                if(n >= 4)
                                        n = 0;
                                break out;
                        }
                }
        }
}


# 
# FUNCTION:	errnotify()
#
# PURPOSE:	Notify the user that an error has occurred.
#
#
errnotify (ctxt: ref Context, title, msg: string)
{

        ldisp := ctxt.display;
        ones = ldisp.color(draw->White);
 
        noentry := ldisp.open("/icons/noentry.bit");
        if(noentry == nil)
                return;
 
        lightyellow := ldisp.rgb(255, 255, 180-32);
        lightbluegreen := ldisp.rgb(161, 195, 209);
 
        font := Font.open(ctxt.display, "*default*");
	if (font == nil) {
		sys->fprint (stderr,"Failed to open *default* font\n");
		return;
	}
        errstyle := ref Style(
                        font,                           # titlefont
                        font,                           # textfont
                        # lightbluegreen,                 # screencolor
                        ldisp.color(draw->White),     # elemcolor
                        ldisp.color(draw->Red),       # edgecolor
                        ldisp.color(draw->Black),     # titlecolor
                        ldisp.color(draw->Black),     # textcolor
                        lightyellow);                   # highlightcolor
 
        errenv := ref Environ(ctxt.screen, errstyle);
        le := Element.elist(errenv, nil, Prefab->EHorizontal);
        le.append(Element.icon(errenv, noentry.r, noentry, ones));
        msg = "\n"+msg+"\n\n";
        le.append(Element.text(errenv, msg, ((0, 0), (400, 0)), Prefab->EText));
        le.adjust(Prefab->Adjpack, Prefab->Adjleft);
        c := Compound.box(errenv, (100, 100), Element.text(errenv, title, ((0,0),(0,
0)), Prefab->ETitle), le);
        c.draw();
        <-ctxt.cir;
}


#
# FUNCTION:	delHdr()
#
# PURPOSE:	updates hdrs array to reflect a deletion of a message
#
#
delHdr (num: int, ohdrs: array of string) : array of string
{
	n := len ohdrs;
	nhdrs := array[n-1] of string;
	j := 0;
	for (i := 0; i < n; i++) {
		if (i != num-1)
			nhdrs[j++] = ohdrs[i];
	}
	return nhdrs;
}

