implement Register;

include "sys.m";
FD: import Sys;
sys: Sys;

include "draw.m";
draw: Draw;
Display, Font, Screen, Image: import draw;

include "keyring.m";
kr: Keyring;
IPint: import kr;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;
include "mux.m";
	mux: Mux;
	Context: import mux;

include "ir.m";

include "security.m";
virgil: Virgil;
random: Random;

include "string.m";
str: String;

Register: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

stderr, stdin, stdout: ref FD;
screen: ref Screen;
display: ref Display;
windows: array of ref Image;
env: ref Environ;
ones: ref Image;
slavectl: chan of int;
contxt: ref Context;
isscreen: int;

init(ctxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	if(ctxt == nil || ctxt.screen == nil)
		isscreen = 0;
	else
		isscreen = 1;

	if(isscreen){
		draw = load Draw Mux->PATH;
		screen = ctxt.screen;
		display = ctxt.display;
		contxt = ctxt;
		env = mkenv();

		ones = display.color(draw->Transparent);
	}

	stdin = sys->fildes(0);
	stdout = sys->fildes(1);
	stderr = sys->fildes(2);

	prefab = load Prefab Prefab->PATH;
	if (prefab == nil) {
		errmsg("registration", "cannot load prefab");
		return;
	}
	mux = load Mux Mux->PATH;
	if (mux == nil) {
		errmsg("registration", "cannot load mux");
		return;
	}
	virgil = load Virgil Virgil->PATH;
	if (virgil == nil) {
		errmsg("registration", "cannot load virgil");
		return;
	}
	random = load Random Random->PATH;
	if (random == nil) {
		errmsg("registration", "cannot load random");
		return;
	}
	kr = load Keyring Keyring->PATH;
	if (kr == nil) {
		errmsg("registration", "cannot load kr");
		return;
	}
	str = load String String->PATH;
	if (str == nil) {
		errmsg("registration", "cannot load str");
		return;
	}

	windows = array[3] of ref Image;

	if(isscreen){
		ctxt.ctomux <-= Mux->AMstartir;
		slavectl = chan of int;
		spawn topslave(ctxt.ctoappl, slavectl);
	}

	err := register(argv);
	if(err != nil)
		errmsg("registration", err);
	cleanup();
}

# Pass arguments through to virgil.
register(argv : list of string): string
{
	s: list of string;

	# get box id
	fd := sys->open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return  "can't read nvram";
	buf := array[64] of byte;
	n := sys->read(fd, buf, (len buf) - 1);
	if(n <= 0)
		return "can't read nvram";
	boxid := string buf[0:n];
	fd = nil;
	buf = nil;

	s = "yes" :: ("no" :: s);
	case dialogue("Register with your service provider?", s, 0) {
	0 =>
		;
	* =>
		return nil;
	}
	s = nil;

	# a holder
	info := ref Keyring->Authinfo;

	targv := str->append("$SIGNER", argv);
	if (targv == nil)
		return "cannot append $SIGNER to argv";

	# contact signer
	status("looking for signer");
	signer := virgil->virgil(targv);
	targv = nil;
	if(signer == nil)
		return "can't find signer";
	status("dialing tcp!"+signer+"!infsigner");
	(ok, c) := sys->dial("tcp!"+signer+"!infsigner", nil);
	if(!ok)
		return "can't contact signer";

	# get signer's public key and diffie helman parameters
	status("getting signer's key");
	spkbuf := kr->getmsg(c.dfd);
	if(spkbuf == nil)
		return "can't read signer's key";
	info.spk = kr->strtopk(string spkbuf);
	if(info.spk == nil)
		return "bad key from signer";
	alphabuf := kr->getmsg(c.dfd);
	if(alphabuf == nil)
		return "can't read dh alpha";
	info.alpha = IPint.b64toip(string alphabuf);
	pbuf := kr->getmsg(c.dfd);
	if(pbuf == nil)
		return "can't read dh mod";
	info.p = IPint.b64toip(string pbuf);
	if(info.p == nil)
		return "can't read diffie hellman parameters";

	# generate our key from system parameters
	status("generating our key");
	info.mysk = kr->genSKfromPK(info.spk, boxid);
	if(info.mysk == nil)
		return "can't generate our own key";
	info.mypk = kr->sktopk(info.mysk);

	# send signer our public key
	mypkbuf := array of byte kr->pktostr(info.mypk);
	kr->sendmsg(c.dfd, mypkbuf, len mypkbuf);

	# get blind certificate
	status("getting blinded certificate");
	certbuf := kr->getmsg(c.dfd);
	if(certbuf == nil)
		return "can't read signed key";

	# verify we've got the right stuff
	if(!verify(boxid, spkbuf, mypkbuf, certbuf))
		return "verification failed, try again";

	# contact counter signer
	status("dialing tcp!"+signer+"!infsigner");
	(ok, c) = sys->dial("tcp!"+signer+"!infcsigner", nil);
	if(!ok)
		return "can't contact countersigner";

	# send boxid
	buf = array of byte boxid;
	kr->sendmsg(c.dfd, buf, len buf);

	# get blinding mask
	status("unblinding certificate");
	mask := kr->getmsg(c.dfd);
	if(len mask != len certbuf)
		return "bad mask length";
	for(i := 0; i < len mask; i++)
		certbuf[i] = certbuf[i] ^ mask[i];
	info.cert = kr->strtocert(string certbuf);

	status("verifying certificate");
	state := kr->sha(mypkbuf, len mypkbuf, nil, nil);
	if(kr->verify(info.spk, info.cert, state) == 0)
		return "bad certificate";

	status("storing keys");
	kr->writeauthinfo("/nvfs/default", info);
	
	status("Congratulations, you are registered.");

	return nil;
}

cleanup()
{
	if(!isscreen)
		return;
	slavectl <-= Mux->AMexit;
	contxt.ctomux <-= Mux->AMexit;
}

mkenv(): ref Environ
{
	lightyellow := display.rgb(255, 255, 180-32);

	font := Font.open(display, "*default*");
	style := ref Style(
			font,				# titlefont
			font,				# textfont
			display.color(draw->White),	# elemcolor
			display.color(draw->Blue),	# edgecolor
			display.color(draw->Black),	# titlecolor	
			display.color(draw->Black),	# textcolor
			display.color(draw->Green));	# highlightcolor

	return ref Environ(screen, style);
}

errmsg(title,msg: string)
{
	if(!isscreen){
		sys->fprint(stderr, "%s: %s\n", title, msg);
		return;
	}

	noentry := display.open("/icons/noentry.bit");
	if(noentry == nil)
		return;

	le := Element.elist(env, nil, Prefab->EHorizontal);
	le.append(Element.icon(env, noentry.r, noentry, ones));
	msg = "\n"+msg+"\n\n";
	le.append(Element.text(env, msg, ((0, 0), (400, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);
	c := Compound.box(env, (100, 100), Element.text(env, title, ((0,0),(0,0)), Prefab->ETitle), le);
	c.draw();
	windows[1] = c.image;
	<-contxt.cir;
}

dialogue(expl: string, selection: list of string, width: int): int
{
	if(!isscreen)
		return txtdialogue(expl, selection);

	if(width == 0)
		width = 200;

	regpic := display.open("/icons/register.bit");
	if(regpic == nil)
		return -1;
	title := Element.elist(env, nil, Prefab->EHorizontal);
	title.append(Element.icon(env, regpic.r, regpic, ones));
	title.append(Element.text(env, expl, ((0,0),(width,0)), Prefab->ETitle));
	title.adjust(Prefab->Adjpack, Prefab->Adjleft);

	le := Element.elist(env, nil, Prefab->EHorizontal);
	while(selection != nil){
		le.append(Element.text(env, hd selection, ((0, 0), (0, 0)), Prefab->EText));
		selection = tl selection;
	}
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);
	c := Compound.box(env, (100, 100), title, le);
	c.draw();
	windows[0] = c.image;
	for(;;){
		(key, index, nil) := c.select(le, 0, contxt.cir);
		case key {
		Ir->Select =>
			windows[0] = nil;
			return index;
		Ir->Enter =>
			windows[0] = nil;
			return -1;
		}
	}
}

txtdialogue(expl: string, selection: list of string): int
{
	sys->fprint(stdout, "%s: (", expl);
	l := selection;
	while(l != nil){
		sys->fprint(stdout, "%s", hd l);
		l = tl l;
		if(l != nil)
			sys->fprint(stdout, ", ");
	}
	sys->fprint(stdout, "): ");

	reply := readline();
	n := len reply;

	l = selection;
	#matches on leading slice
	for(i := 0; l != nil; i++){
		if((hd l)[0:n] == reply)
			break;
		l = tl l;
	}

	return i;
}

readline(): string
{
	reply : string;

	reply = nil;
	buf := array[1] of byte;
	for(;;){
		if(sys->read(stdin, buf, 1) != 1)
			break;
		if('\r' == int buf[0] || '\n' == int buf[0])
			break;
		reply = reply + string buf;
	}
	return reply;
}

status(expl: string)
{
	if(!isscreen){
		sys->fprint(stdout, "registration status: %s\n", expl);
		return;
	}

	regpic := display.open("/icons/register.bit");
	if(regpic == nil)
		return;
	title := Element.elist(env, nil, Prefab->EHorizontal);
	title.append(Element.icon(env, regpic.r, regpic, ones));
	title.append(Element.text(env, "registration\nstatus", ((0,0),(0,0)), Prefab->ETitle));
	title.adjust(Prefab->Adjpack, Prefab->Adjleft);

	c := Compound.box(env, (100, 100), title, Element.text(env, expl, ((0,0),(0,0)), Prefab->ETitle));
	c.draw();
	windows[0] = c.image;
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

pro:= array[] of {
	"alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf",
	"hotel", "india", "juliet", "kilo", "lima", "mike", "nancy", "oscar",
	"poppa", "quebec", "romeo", "sierra", "tango", "uniform",
	"victor", "whiskey", "xray", "yankee", "zulu"
};

#
#  prompt for acceptance
#
verify(boxid: string, hispk, mypk, cert: array of byte): int
{
	s: string;

	if(!isscreen)
		return txtverify(boxid, hispk, mypk, cert);

	# hash the string
	state := kr->md5(hispk, len hispk, nil, nil);
	kr->md5(mypk, len mypk, nil, state);
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(cert, len cert, digest, state);

	regpic := display.open("/icons/register.bit");
	if(regpic == nil)
		return -1;
	title := Element.elist(env, nil, Prefab->EVertical);
	subtitle := Element.elist(env, nil, Prefab->EHorizontal);
	subtitle.append(Element.icon(env, regpic.r, regpic, ones));
	subtitle.append(Element.text(env, "Telephone your service provider\n to register.  You will need\nthe following:\n", ((0,0),(0,0)), Prefab->ETitle));
	subtitle.adjust(Prefab->Adjpack, Prefab->Adjleft);
	title.append(subtitle);


	line := Element.text(env, "boxid is '"+boxid+"'.", ((0,0),(0,0)), Prefab->ETitle);
	title.append(line);
	for(i := 0; i < len digest; i++){
		line = Element.elist(env, nil, Prefab->EHorizontal);
		s = (string (2*i)) + ": " + pro[((int digest[i])>>4)%len pro];
		line.append(Element.text(env, s, ((0,0),(0,0)), Prefab->ETitle));

		s = (string (2*i+1)) + ": " + pro[(int digest[i])%len pro] + "\n";
		line.append(Element.text(env, s, ((0,0),(200,0)), Prefab->ETitle));

		line.adjust(Prefab->Adjequal, Prefab->Adjleft);
		title.append(line);
	}
	title.adjust(Prefab->Adjpack, Prefab->Adjleft);

	le := Element.elist(env, nil, Prefab->EHorizontal);
	le.append(Element.text(env, " accept ", ((0, 0), (0, 0)), Prefab->EText));
	le.append(Element.text(env, " reject ", ((0, 0), (0, 0)), Prefab->EText));
	le.adjust(Prefab->Adjpack, Prefab->Adjleft);

	c := Compound.box(env, (50, 50), title, le);
	c.draw();
	windows[0] = c.image;

	for(;;){
		(key, index, nil) := c.select(le, 0, contxt.cir);
		case key {
		Ir->Select =>
			windows[0] = nil;
			if(index == 0)
				return 1;
			return 0;
		Ir->Enter =>
			windows[0] = nil;
			return 0;
		}
	}

	return 0;
}

txtverify(boxid: string, hispk, mypk, cert: array of byte): int
{
	s: string;

	# hash the string
	state := kr->md5(hispk, len hispk, nil, nil);
	kr->md5(mypk, len mypk, nil, state);
	digest := array[Keyring->MD5dlen] of byte;
	kr->md5(cert, len cert, digest, state);

	for(i := 0; i < len digest; i++){
		s = s + (string (2*i)) + ": " + pro[((int digest[i])>>4)%len pro] + "\t";
		s = s + (string (2*i+1)) + ": " + pro[(int digest[i])%len pro] + "\n";
	}

	sys->fprint(stdout, "boxid is '%s'\n\n", boxid);
	sys->fprint(stdout, "%s\naccept (y or n)? ", s);
	reply := readline();
	if(reply != "y"){
		sys->fprint(stderr, "\nrejected\n");
		return 0;
	}
	return 1;
}
