implement Web;

starturl: con "http://google.com";


include "sys.m";
sys:	Sys;
print, sprint: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ, Layout: import prefab;

include "string.m";
stringmod: String;

include "url.m";
urlmod: Url;
ParsedUrl: import urlmod;

include "webget.m";

include "html.m";
html: HTML;
Lex, RBRA, globalattr, lex, attrvalue, isbreak: import html;

include "ir.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

DEBUG: con 1;

Web: module
{
	init:	fn(ctxt: ref Context, args: list of string);
};

Indent: con "    ";

Roman: con 0;
Bold: con 1;
Italic: con 2;
Typewriter: con 3;

XOffset: con 20;
YOffset: con 10;
Scroll: con 150;
Width: int;
Height: int;

Basesize: con 3;	# default BASEFONT size
Small, Normal, Large, Verylarge, NSIZE: con iota;

pointsize:= array[] of { 6, 9, 10, 12 };
roman:= array[NSIZE] of ref Font;
bold:= array[NSIZE] of ref Font;
italic:= array[NSIZE] of ref Font;
typewriter:= array[NSIZE] of ref Font;

screen: ref Screen;
display: ref Display;
ones, zeros, black, white, blue, red, yellow, green: ref Image;
lightbluegreen, softblue, orange: ref Image;
lightgrey, darkgreen, vdarkgreen, darkblue: ref Image;
mainfont: ref Font;
ctxt:	ref Context;
slavectl:	chan of int;
webio:	ref Sys->FD;

windows: array of ref Image;
Winfo, Wmain, Nwindows:	con iota;

hex(c: int): int
{
	if('0'<=c && c<='9')
		return c-'0';
	if('a'<=c && c<='f')
		return 10+(c-'a');
	if('A'<=c && c<='F')
		return 10+(c-'A');
	return 0;
}

rgbhex(s: string): ref Image
{
	r,g,b: int;
	case len s {
	* =>
		return nil;
	7 =>
		if(s[0]!='#')
			return nil;
		r = hex(s[1])*16+hex(s[2]);
		g = hex(s[3])*16+hex(s[4]);
		b = hex(s[5])*16+hex(s[6]);
	4 =>
		if(s[0]!='#')
			return nil;
		r = hex(s[1])*16+hex(s[1]);
		g = hex(s[2])*16+hex(s[2]);
		b = hex(s[3])*16+hex(s[3]);
	}
	return display.rgb(r, g, b);
}

getcolor(html: array of ref Lex, name: string, def: ref Image): ref Image
{
	color := def;
	(nil, value) := globalattr(html, HTML->Tbody, name);
	if(value != ""){
		t := rgbhex(value);
		if(t != nil)
			color = t;
	}
	return color;
}

buildpage(base, url: string): (string, ref Compound)
{
	(doctype, nbase, clen) := webheader(base, url, "text/html,text/plain,image/x-compressed");
	if(doctype==nil){
		error("no page '"+doctype+"'", url);
		return (nil, nil);
	}
	style := ref Style(
			getfont(Bold, Basesize, Large),	# titlefont
			mainfont,			# textfont
			lightgrey,			# elemcolor
			darkgreen,		# edgecolor
			vdarkgreen,		# titlecolor
			black,			# textcolor
			orange);			# highlightcolor
	env := ref Environ(screen, style);
	e: ref Element;
	title := "";
	if(doctype == "image/x-compressed" || doctype == "image/x-compressed2"){
		pic := display.readimage(webio);
		if (DEBUG) {
			if(pic == nil) sys->print("readimage fails %r\n");
			else sys->print("readimage succeeds\n");
		}
		mask := ones;
		if(doctype == "image/x-compressed2") {
			mask = display.readimage(webio);
			if (DEBUG){
				if(mask == nil) sys->print("readimage of mask fails %r\n");
				else sys->print("readimage of mask succeeds\n");
			}
		}
		e = Element.icon(env, pic.r, pic, mask);
		title = "Image";
	}
	else {
		b := webcontents(clen);
		if(doctype!="text/html" && doctype!="text/plain"){
			error("Unexpected type '"+doctype+"'", nbase);
			return (nil, nil);
		}
		toks := lex(b, HTML->Latin1, 0);
		if(toks == nil)
			return (nil, nil);

		base = nbase;
		(nil, value) := globalattr(toks, HTML->Tbase, "href");
		if(value != "")
			base = value;

		elemcolor: ref Image = nil;
		(nil, value) = globalattr(toks, HTML->Tbody, "background");
		if(value != ""){
			(elemcolor, nil) = readimage(base, value);
			if(elemcolor != nil){
				elemcolor.repl = 1;
				elemcolor.clipr = ((-10000,-10000),(10000,10000));
			}
		}

		bgcolor := getcolor(toks, "bgcolor", nil);
		if(bgcolor != nil)
			elemcolor = bgcolor;
		if(elemcolor != nil)
			style.elemcolor = elemcolor;
		textcolor := getcolor(toks, "text", black);
		anchorcolor := getcolor(toks, "link", darkblue);

		(e, title) = assemble(base, env, Element.elist(env, nil, Prefab->EVertical), toks, "Untitled", textcolor, anchorcolor);
	}

	e.adjust(Prefab->Adjpack, Prefab->Adjup);
	t := Element.text(env, title, ((0,0), (0, 0)), Prefab->ETitle);
	if(e.r.dy() > Height-t.r.dy())
		e.clip(((0, 0), (Width, Height-t.r.dy())));
	c := Compound.box(env, (XOffset,YOffset), t, e);
	windows[Winfo] = nil;
	c.draw();
	return (base, c);
}

truesize(fontsize: int): int
{
	if(fontsize < 3)
		return Small;
	if(fontsize < 5)
		return Normal;
	if(fontsize < 7)
		return Large;
	return Verylarge;
}

fontsize(base, cur: int, new: string): int
{
	if(len new < 1)
		return cur;
	if(new[0] == '+')
		return base+int new[1:len new];
	if(new[0] == '-')
		return base-int new[1:len new];
	return int new;
}

assemble(base: string, env: ref Environ, v: ref Element, html: array of ref Lex, title: string, textcolor, anchorcolor: ref Image): (ref Element, string)
{
	l: list of Layout;
	color := black;
	centering := 0;
	listtype: list of int;
	listctr: list of int;
	value: string;
	img, mask: ref Image;
	basesize := 3;
	size:= (basesize) :: nil;
	fontstyle := Roman;
	font := getfont(Roman, basesize, Normal);
	tag := "";
	prefix := Layout (font, color, "", nil, nil, tag);

	ctr := 0;
	for(i:=0; i<len html; i++){
		h := html[i];
		cmd := h.tag;
		case cmd{
		HTML->Data =>
			if(prefix.text!="" && prefix.text[0]=='\n' &&  h.text!="" && h.text[0]=='\n')
				prefix.text = prefix.text[1:len prefix.text];
			if(len h.text>1 && h.text[len h.text-1]=='\n')
				h.text[len h.text-1] = ' ';
			if(prefix.text=="" || (prefix.font==font && prefix.color==color))
				l = (font, color, prefix.text+h.text, nil, nil, tag) :: l;
			else
				l = (font, color, h.text, nil, nil, tag) :: prefix :: l;
			prefix = (font, color, "", nil, nil, tag);
			if(centering && isbreak(html, i))
				(nil, l) = addtext(env, v, prefix, l, listtype, 1);
		HTML->Timg =>
			(img, mask, value) = image(base, color, h, listtype);
			if(img != nil){
				if(prefix.text != "")
					l = prefix :: l;
				l = (font, color, "", img, mask, tag) :: l;
			}else if(value != ""){
				if(prefix.text=="" || (prefix.font==font && prefix.color==color))
					l = (font, color, prefix.text+value, nil, nil, tag) :: l;
				else
					l = (font, color, value, nil, nil, tag) :: prefix :: l;
			}
			prefix = (font, color, "", nil, nil, tag);
			if(centering && isbreak(html, i))
				(nil, l) = addtext(env, v, prefix, l, listtype, 1);
		HTML->Tbasefont =>
			(nil, value) = attrvalue(h.attr, "size");
			if(value != nil){
				s := int value;
				if(0<=s && s<=7)
					basesize = int value;
			}
		HTML->Tfont =>
			(nil, value) = attrvalue(h.attr, "size");
			if(value != nil){
				size = fontsize(basesize, hd size, value) :: size;
				font = getfont(fontstyle, -1, truesize(hd size));
			}
		HTML->Tfont+RBRA =>
			if(len size > 1){
				size = tl size;
				font = getfont(fontstyle, -1, truesize(hd size));
			}
		HTML->Tem or HTML->Ti or HTML->Tcite =>
			font = getfont(fontstyle=Italic, basesize, Normal);
		HTML->Tstrong or HTML->Tb =>
			font = getfont(fontstyle=Bold, basesize, Normal);
		HTML->Ttt or HTML->Tcode or HTML->Tkbd or HTML->Tsamp =>
			font = getfont(fontstyle=Typewriter, basesize, Normal);
		HTML->Tem+RBRA or HTML->Ti+RBRA or HTML->Tb+RBRA or HTML->Tstrong+RBRA or HTML->Ttt+RBRA or
		HTML->Tcite+RBRA or HTML->Tcode+RBRA or HTML->Tkbd+RBRA =>
			font = getfont(fontstyle=Roman, basesize, Normal);
		HTML->Th1 =>
			font = getfont(fontstyle=Bold, basesize, Verylarge);
			prefix = (font, color, prefix.text+"\n       ", nil, nil, tag);
		HTML->Th2 =>
			font = getfont(fontstyle=Bold, basesize, Large);
			prefix = (font, color, prefix.text+"\n", nil, nil, tag);
		HTML->Th3 =>
			font = getfont(fontstyle=Italic, basesize, Large);
			prefix = (font, color, prefix.text+"\n  ", nil, nil, tag);
		HTML->Th4 =>
			font = getfont(fontstyle=Bold, basesize, Normal);
			prefix = (font, color, prefix.text+"\n    ", nil, nil, tag);
		HTML->Th5 =>
			font = getfont(fontstyle=Italic, basesize, Normal);
			prefix = (font, color, prefix.text+"\n    ", nil, nil, tag);
		HTML->Th6 =>
			font = getfont(fontstyle=Bold, basesize, Normal);
			prefix = (font, color, prefix.text+"\n", nil, nil, tag);
		HTML->Tpre =>
			# not enough done here; must prevent fill!
			font = getfont(fontstyle=Typewriter, basesize, Normal);
			prefix = (font, color, prefix.text+"\n", nil, nil, tag);
		HTML->Th1+RBRA or HTML->Th2+RBRA or HTML->Th3+RBRA or HTML->Th4+RBRA or HTML->Tpre+RBRA =>
			font = getfont(fontstyle=Roman, basesize, Normal);
			prefix = (font, color, prefix.text+"\n", nil, nil, tag);
		HTML->Th5+RBRA or HTML->Th6+RBRA =>
			break;
		HTML->Tbr or HTML->Tbody =>
			prefix = (font, color, prefix.text+"\n", nil, nil, tag);
		HTML->Tp =>
			prefix = (font, color, prefix.text+"\n  ", nil, nil, tag);
		HTML->Ta =>
			color = anchorcolor;
			(nil, tag) = attrvalue(h.attr, "href");
		HTML->Ta+RBRA =>
			color = textcolor;
			tag = "";
		HTML->Ttitle =>
			i++;
			title = html[i].text;
		HTML->Thr =>
			(prefix, l) = addtext(env, v, prefix, l, listtype, centering);
			rule := horizrule(env);
			v.append(rule);
		HTML->Tul or HTML->Tol or HTML->Tmenu or HTML->Tblockquote or HTML->Tbq =>
			(prefix, l) = addtext(env, v, prefix, l, listtype, centering);
			listtype = cmd :: listtype;
			listctr = ctr :: listctr;
			ctr = 1;
		HTML->Tul+RBRA or HTML->Tol+RBRA or HTML->Tmenu+RBRA or
		HTML->Tdl+RBRA or HTML->Tblockquote+RBRA or HTML->Tbq+RBRA =>
			(prefix, l) = addtext(env, v, prefix, l, listtype, centering);
			if(listtype!=nil && hd listtype+RBRA==cmd){
				listtype = tl listtype;
				listctr = tl listctr;
			}
		HTML->Tli => {
			lt := 0;
			if(listtype != nil)
				lt = hd listtype;
			case lt{
			HTML->Tmenu =>
				(nil, l) = addtext(env, v, prefix, l, listtype, centering);
				prefix = (font, color, "   ", nil, nil, tag);
			HTML->Tol =>
				(nil, l) = addtext(env, v, prefix, l, listtype, centering);
				prefix = (font, color, string ctr++ + ". ", nil, nil, tag);
			HTML->Tul =>
				(nil, l) = addtext(env, v, prefix, l, listtype, centering);
				prefix = (font, color, "• ", nil, nil, tag);
			}
		}
		HTML->Tdl =>
			;
		HTML->Tdt =>
			(prefix, l) = addtext(env, v, prefix, l, listtype, centering);
			font = getfont(fontstyle=Italic, basesize, Normal);
		HTML->Tdd =>
			(prefix, l) = addtext(env, v, prefix, l, listtype, centering);
			if(listtype==nil || hd listtype!=HTML->Tdl){
				listtype = HTML->Tdl :: listtype;
				listctr = ctr :: listctr;
				ctr = 1;
			}
			font = getfont(fontstyle=Roman, basesize, Normal);
		HTML->Tcenter =>
			if(centering++ == 0)
				(prefix, l) = addtext(env, v, prefix, l, listtype, 0);
		HTML->Tcenter+RBRA =>
			if(centering>0 && centering--==1)
				(prefix, l) = addtext(env, v, prefix, l, listtype, 1);
		HTML->Thtml or HTML->Thtml+RBRA or HTML->Tbody+RBRA or HTML->Taddress or HTML->Taddress+RBRA or
		HTML->Ttitle+RBRA or HTML->Thead or HTML->Thead+RBRA or HTML->Tbase or
		HTML->Tblink or HTML->Tblink+RBRA or HTML->Tli+RBRA or
		HTML->Tmeta or HTML->Tmeta+RBRA or HTML->Tp+RBRA or
		HTML->Tatt_footer or HTML->Tatt_footer+RBRA or
		HTML->Ttable or HTML->Ttable+RBRA or HTML->Ttd or HTML->Ttd+RBRA =>
			;
		* =>
			l = (getfont(Roman, basesize, Normal), green, "<"+h.text+">", nil, nil, "") :: l;
		}
	}
	addtext(env, v, prefix, l, listtype, centering);
	return (v, title);
}

image(base: string, color: ref Image, h: ref Lex, listtype: list of int): (ref Image, ref Image, string)
{
	pic: ref Image;
	mask := ones;
	(nil, url) := attrvalue(h.attr, "src");
	if(url != "")
		(pic, mask) = readimage(base, url);
	if(pic == nil){
		(nil, alternate) := attrvalue(h.attr, "alt");
		if(alternate != nil)
			return (nil, nil, alternate);
		x := len listtype * 15;
		pic = display.newimage(((x,0), (300+x,50)), red.chans, 0, 0);
		pic.draw(pic.r, color, ones, (0,0));
		pic.draw(pic.r.inset(3), lightbluegreen, ones, (0,0));
		pic.text((5+x, 20), black, (0,0), getfont(Roman, -1, Normal), h.text[4:len h.text]);
	}
	return (pic, mask, nil);
}

readimage(base, url: string): (ref Image, ref Image)
{
	if (DEBUG) sys->print("readimage tries %s\n", url);
	(doctype, newurl, clen) := webheader(base, url, "image/x-compressed");
	if (newurl == nil) {
		if (DEBUG)
			sys->print("readimage: header returned nil\n");
		return (nil, nil);
	}
	if(doctype != "image/x-compressed" && doctype != "image/x-compressed2"){
		if (DEBUG)
			sys->print("readimage: doctype %s\n", doctype);
		nil = webcontents(clen);
		return (nil, nil);
	}
	pic := display.readimage(webio);
	if (DEBUG) {
		if(pic == nil) sys->print("readimage fails %r\n");
		else sys->print("readimage succeeds\n");
	}
	mask := ones;
	if(doctype == "image/x-compressed2"){
		mask = display.readimage(webio);
		if (DEBUG){
			if(mask == nil) sys->print("readimage of mask fails %r\n");
			else sys->print("readimage of mask succeeds\n");
		}
	}
	return (pic, mask);
}

horizrule(env: ref Environ): ref Element
{
	pic := display.newimage(((0,0), (Width,2)), red.chans, 0, Draw->Black);
	img := Element.icon(env, pic.r, pic, ones);
	img.clip(img.r.inset(-2));
	return img;
}

addtext(env: ref Environ, v: ref Element, prefix: Layout, l: list of Layout, listtype: list of int, centering: int): (Layout, list of Layout)
{
	if(prefix.text != "")
		l = prefix :: l;
	if(l == nil)
		return ((prefix.font, prefix.color, "", nil, nil, ""), nil);
	# list is in reverse order; reverse yet again
	rl: list of Layout;
	rl = nil;
	while(l != nil){
		rl = hd l :: rl;
		l = tl l;
	}
	wid := Width;
	if(centering)
		wid = 0;
	x := len listtype * prefix.font.width(Indent);
	e := Element.layout(env, rl, ((x,0), (wid-x, 0)), Prefab->EText);
	if(centering)
		e = center(env, e);
	v.append(e);
	return ((prefix.font, prefix.color, "", nil, nil, ""), nil);
}

center(nil: ref Environ, e: ref Element): ref Element
{
	r := e.r;
	dx := r.dx();
	if(dx>= 2*2+Width)
		return e;
	dx = (2*2+Width) - dx;
	e.translate((dx/2, 0));
	return e;
}

topslave()
{
	for(;;)
		alt{
		m := <-ctxt.ctoappl =>
			if(m == Mux->MAtop)
				screen.top(windows);
		<-slavectl =>
			return;
		}
}

#msgslave(c: chan of (int, string, string))
#{
#	style := ref Style(
#			getfont(Bold, Basesize, Large),	# titlefont
#			mainfont,			# textfont
#			white,			# elemcolor
#			darkgreen,		# edgecolor
#			vdarkgreen,		# titlecolor
#			black,			# textcolor
#			orange);		# highlightcolor
#	env := ref Environ(screen, style);
#
#	for(;;){
#		(t, msg, url) := <-c;
#		if(t == Webget->Exit)
#			return;
#		w := Compound.textbox(env, Rect((10, 50),(500, 50)), msg+"...", url);
#		if(w == nil)
#	                return;
#
#		w.draw();
#		windows[Winfo] = w.image;
#		w = nil;
#	}
#}

error(msg, url: string)
{
	if(DEBUG)
		sys->print("ERROR: %s: %s\n", url, msg);
	style := ref Style(
			getfont(Bold, Basesize, Large),	# titlefont
			mainfont,			# textfont
			white,			# elemcolor
			darkgreen,		# edgecolor
			vdarkgreen,		# titlecolor
			black,			# textcolor
			orange);		# highlightcolor
	env := ref Environ(screen, style);

	w := Compound.textbox(env, Rect((10, 50),(500, 50)), msg, url);
	if(w == nil)
                return;

	w.draw();
	windows[Winfo] = w.image;
	w = nil;
}

# variables used to navigate list of pages
NURL: con 100;
url := starturl;
base := starturl;
bases := array[NURL] of string;
urls := array[NURL] of string;
maxurlno := -1;
urlno := 0;
lasturl := -1;
main: ref Compound;

init(actxt: ref Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
	prefab = load Prefab Prefab->PATH;
	html = load HTML HTML->PATH;
	stringmod = load String String->PATH;
	urlmod = load Url Url->PATH;
	if(html==nil || urlmod==nil){
		print("can't load web modules: %r\n");
		ctxt.ctomux <-= Mux->AMexit;
		return;
	}
	urlmod->init();
	if(len argv > 1){
		url = hd tl argv;
		for(i:=0; i<len url; i++)
			if(url[i] == '$')
				url[i] = ':';
	}

	ctxt = actxt;
	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[Nwindows] of ref Image;
	ones = display.color(draw->White);
	zeros = display.color(draw->Black);
	black = display.color(draw->Black);
	white = display.color(draw->White);
	blue = display.color(draw->Blue);
	red = display.color(draw->Red);
	yellow = display.color(draw->Yellow);
	green = display.color(draw->Green);
	lightgrey = display.color(16r22);
	darkgreen = display.color(246);
	vdarkgreen = display.color(234);
	darkblue = display.color(249);	
	lightbluegreen = display.rgb(161, 195, 209);
	orange = display.rgb(255, 64, 0);
	softblue = display.rgb(115, 168, 201);
	mainfont = Font.open(display, "*default*");
	Width = display.image.r.dx()-2*XOffset;
	Height = display.image.r.dy()-2*YOffset;
	slavectl = chan of int;
	spawn topslave();
	ctxt.ctomux <-= Mux->AMstartir;

	err := webstart();
	if(err != ""){
		print("web: can't start webget: %s: %r\n", err);
		finish();
		return;
	}
	sel := 0;
	key: int;
	e: ref Element;

  Loop:
	for(;;){
		if(lasturl != urlno){
			(nbase, t) := buildpage(base, url);
			if(t==nil && maxurlno<0)
				finish();
			if(t != nil){
				main = t;
				windows[Wmain] = main.image;
				if(urlno>maxurlno && urlno<NURL-1){
					bases[urlno] = base;
					urls[urlno] = url;
					maxurlno = urlno;
				}
				lasturl = urlno;
				base = nbase;
				sel = 0;
				case scroll(ctxt.cir, -1) {
				Ir->ChanDN or Ir->ChanUP =>
					continue Loop;
				}
			}
		}
		(key, sel, e) = main.tagselect(main.contents, sel, ctxt.cir);
		case key {
		Ir->Select =>
			main.contents.show(e);
			base = base;
			url = e.tag;
			urlno = maxurlno+1;
		Ir->Enter or Ir->FF or Ir->Rew or Ir->ChanUP or Ir->ChanDN =>
			scroll(ctxt.cir, key);
		Ir->Error =>
			for(;;){
				key = scroll(ctxt.cir, -1);
				case key {
				Ir->Select=>
					if(urlno > 0){
						urlno--;
						base = bases[urlno];
						url = urls[urlno];
						continue Loop;
					} else
						finish();
				Ir->ChanDN or Ir->ChanUP =>
					continue Loop;
				}
			}
		}
	}
}

scroll(c: chan of int, key: int): int
{
	for(;;){
		case key {
		-1 =>	# no key
			;
		* =>
			return key;
		Ir->Enter =>
			finish();
		Ir->FF =>
			if(main != nil)
				main.scroll(nil, (0, -Scroll));
		Ir->Rew =>
			if(main != nil)
				main.scroll(nil, (0, Scroll));
		Ir->ChanUP =>
			if(urlno < maxurlno){
				urlno++;
				base = bases[urlno];
				url = urls[urlno];
			}
			return key;
		Ir->ChanDN =>
			if(urlno > 0){
				urlno--;
				base = bases[urlno];
				url = urls[urlno];
			}
			return key;
		}
		key = <-c;
	}
}

finish()
{
	ctxt.ctomux <-= Mux->AMexit;
	slavectl <-= Mux->AMexit;	# as good a value as any
	exit;
}

getfont(style, base, size: int): ref Font
{
	name: string;
	font: array of ref Font;
	
	case style{
	Typewriter =>
		name = "latin1CW";
		font = typewriter;
	Roman =>
		name = "unicode";
		font = roman;
	Bold =>
		name = "latin1B";
		font = bold;
	Italic =>
		name = "latin1I";
		font = italic;
	};
	if(base >= 0){
		size = truesize(base)+(size-Normal);
		if(size < Small)
			size = Small;
		if(size > Verylarge)
			size = Verylarge;
	}
	name = sprint("/fonts/lucida/%s.%d.font", name, pointsize[size]);
	font[size] = loadfont(font[size], name);
	return font[size];
}

loadfont(f: ref Font, name: string): ref Font
{
	if(f == nil){
		f = Font.open(display, name);
		if(f == nil)
			f = mainfont;
	}
	return f;
}

webstart(): string
{
	webio = sys->open("/chan/webget", sys->ORDWR);
	if(webio == nil) {
		webget := load Webget Webget->PATH;
		if(webget == nil)
			return ("can't load webget from " + Webget->PATH);
		spawn webget->init(nil, nil);
		ntries := 0;
		while(webio == nil && ntries++ < 10)
			webio = sys->open("/chan/webget", sys->ORDWR);
		if(webio == nil)
			return "error connecting to web";
	}
	return "";
}

webheader(base, url, types: string) : (string, string, int)
{
	n : int;
	s : string;
	u := urlmod->makeurl(url);
	b := urlmod->makeurl(base);
	u.makeabsolute(b);
	savefrag := u.frag;
	u.frag = "";
	loc := u.tostring();
	u.frag = savefrag;
	clen := 0;
	dtype := "";
	nbase := "";
	s = "GET∎0∎id1∎" + loc + "∎" + types + "∎max-stale=3600\n";
	if(DEBUG)
		sys->print("webget request: %s", s);
	bs := array of byte s;
	n = sys->write(webio, bs, len bs);
	if(n < 0)
		error(sys->sprint("error writing webget request: %r"), loc);
	else {
		bstatus := array[1000] of byte;
		n = sys->read(webio, bstatus, len bstatus);
		if(n < 0)
			error(sys->sprint("error reading webget response header: %r"), loc);
		else {
			status := string bstatus[0:n];
			if(DEBUG)
				sys->print("webget response: %s\n", status);
			(nl, l) := sys->tokenize(status, " \n");
			if(nl < 3)
				error("unexpected webget response: " + status, loc);
			else {
				s = hd l;
				l = tl l;
				if(s == "ERROR") {
					(nil, msg) := stringmod->splitl(status[6:], " ");
					error(msg, loc);
				}
				else if(s == "OK") {
					clen = int (hd l);
					l = tl(tl l);
					dtype = hd l;
					l = tl l;
					nbase = hd l;
				}
				else
					error("webget protocol error", loc);
			}
		}
	}
	return (dtype, nbase, clen);
}

webcontents(clen: int) : array of byte
{
	contents := array[clen] of byte;
	i := 0;
	n := 0;
	while(i < clen) {
		n = sys->read(webio, contents[i:], clen-i);
		if(n < 0)
			break;
		i += n;
	}
	return contents;
}
