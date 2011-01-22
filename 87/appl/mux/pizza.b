implement MomsPizza;

include "sys.m";
sys: Sys;
print, sprint, tokenize: import sys;

include "draw.m";
draw: Draw;
Display, Font, Rect, Point, Image, Screen: import draw;

include "prefab.m";
prefab: Prefab;
Style, Element, Compound, Environ: import prefab;

include "bufio.m";
bufio: Bufio;
Iobuf: import bufio;

include "ir.m";

include "mux.m";
	mux: Mux;
	Context: import mux;

dir: con "/services/pizza/";

MomsPizza: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

Menu: adt
{
	tag:	string;		# Identifies menu item uniquely
	nsel:	int;		# Number of selectable items,
				# if zero, then this is a leaf node.
	cursel:	int;		# Current selection (if non leaf)
};

screen:		ref Screen;
display:	ref Display;
windows:	array of ref Image;
style:		Style;
ones,zeroes:	ref Image;
zr:		Rect;
#icon:		ref Draw->Image;
iconfile:	string = nil;

menu :=		array[256] of Menu;
nmenu :=	0;

salestax:	con real 0.06;

makemenu(ctxt: ref Context, file: string): int
{
	s:	string;
	i, j, k:int;
	myr:	Rect;
	el:	ref Element;
	env:	ref Environ;

	if (file == "show.menu") return makeshow(ctxt);
	if (file == "done.menu") return makedone(ctxt);

	fd := bufio->open(dir+file, bufio->OREAD);
	if(fd == nil) {
		print("open menu: %r");
		return -1;
	}
	mystyle := style;

	icon: ref Image;
	for (i=0; (s = fd.gets('\n')) != nil; i++) {
		(n, field) := tokenize(s, ":");
		if (n != 6) {
			print("wrong number of fields in menu %s\n", dir+file);
			return -1;
		}
		tag := hd field; field = tl field;
		xmin := int hd field; field = tl field;
		ymin := int hd field; field = tl field;
		xmax := int hd field; field = tl field;
		ymax := int hd field; field = tl field;
		r := ((xmin,ymin),(xmax,ymax));
		f := hd field;
		if (f[len f -1] == '\n') f = f[0:len f -1];

		if (iconfile != dir + f) {
			iconfile = dir + f;
			icon = display.open(iconfile);
			if (icon == nil) {
				print("Can't open icon %s: %r\n", dir + f);
				iconfile = nil;
				return -1;
			}
		}
		for (j=0; j<nmenu; j++)
			if (menu[j].tag == tag)
				break;
		if (j == nmenu) {
			nmenu++;
			menu[j].tag = tag;
			menu[j].nsel = 0;
		}
		if (i == 0) {
			k = j;
			menu[k].cursel = 0;
			mystyle.elemcolor = icon;
			myr = r;
			env = ref Environ(ctxt.screen, ref mystyle);
			el = Element.elist(env, nil, Prefab->EVertical);
		} else {
			menu[k].nsel++;
			ei := Element.icon(env, r, icon, zeroes);
			ei.tag = tag;
			el.append(ei);
		}
	}
	el.clip(myr);
	cmpnd = Compound.box(env, myr.min, nil, el);
	return k;
}

calculate(): (real, real, real)
{
	subtotal := 0.0;
	for (o := order; o != nil; o = tl o) {
		item := hd o;
		item.total = item.price * real item.n;
		if (item.tag[0:4] == "stuf")
			i := -1;
		else
			i = -2;
		for (oo := item.subitem; oo != nil; oo = tl oo) {
			subitem := hd oo;
			j := subitem.n;
			while (i < 0 && j > 0) { i++; j--; }
			subitem.total = (real j)*subitem.price;
			item.total += subitem.total * real item.n;
		}
		subtotal += item.total;
	}
	return (subtotal, salestax*subtotal, subtotal + salestax*subtotal);
	
}

makeshow(ctxt: ref Context): int
{
	j: int;

	for (j=0; j<nmenu; j++)
		if (menu[j].tag == "show")
			break;
	if (j == nmenu) {
		nmenu++;
		menu[j].tag = "show";
	}
	menu[j].nsel = 0;

	mystyle := style;
	(subtotal, tax, grandtotal) := calculate();

	white := display.color(draw->White);
	env := ref Environ(ctxt.screen, ref mystyle);
	el := Element.elist(env, nil, Prefab->EVertical);
	icon := display.open(dir + "order-head.bit");
	el.append(Element.icon(env, zr, icon, ones));
	el.append(Element.separator(env, ((0,0),(640,20)), white, zeroes));

	if (order == nil) {
		el.append(Element.text(env,
			"Nothing yet.  Why don't you do something about it!",
			((32,0),(0,0)), Prefab->EText));
		menu[j].cursel = 1;
	}

	for (o := order; o != nil; o = tl o) {
		item := hd o;
		ei := Element.elist(env, nil, Prefab->EHorizontal);
		if (item.n)
			s := sprint("%2d  %s", item.n, item.item);
		else
			s = sprint("%2d  (%s)", item.n, item.item);
		ei.append(Element.text(env, s, ((32,0),(0,0)), Prefab->EText));
		ne := Element.text(env, sprint("$%6.2f", item.total),
			((0,0), (0, 0)), Prefab->EText);
		ne.translate((540-ne.r.max.x, 0));
		ei.append(ne);
		ei.clip(((32,0),(608, 25)));
		ei.tag = "number";
		el.append(ei);
		menu[j].nsel++;
		for (oo := item.subitem; oo != nil; oo = tl oo) {
			subitem := hd oo;
			if (subitem.n) {
				if (subitem.total != 0.0)
				    s = sprint("%d  %s ($%6.2f)",
					subitem.n, subitem.item, subitem.total);
				else
				    s = sprint("%d  %s",
					subitem.n, subitem.item);
			} else
				s = sprint("%d  (%s)", subitem.n, subitem.item);
			ei = Element.text(env, s, ((64,0),(0,0)),
				Prefab->EText);
			ei.tag = "number";
			ei.clip(((32,0),(608, 25)));
			el.append(ei);
			menu[j].nsel++;
		}
	}

	el.adjust(Prefab->Adjpack, Prefab->Adjup);

	((x1,y1),(x2,y2)) := el.r;
	icon = display.open(dir + "order-tail.bit");
	el.append(Element.icon(env, ((0,y2),(0,0)), icon, ones));

	dy := icon.r.max.y;
	r := ((x1,y1),(x2,y2+dy));
	el.clip(r);

	s := sprint("%6.2f", subtotal);
	ei := Element.text(env, s, ((0,0),(0,0)), Prefab->EText);
	ei.translate((240-ei.r.max.x, y2+54));
	el.append(ei);
	s = sprint("%6.2f", tax);
	ei = Element.text(env, s, ((0,0),(0,0)), Prefab->EText);
	ei.translate((240-ei.r.max.x, y2+80));
	el.append(ei);
	s = sprint("%6.2f", grandtotal);
	ei = Element.text(env, s, ((0,0),(0,0)), Prefab->EText);
	ei.translate((240-ei.r.max.x, y2+106));
	el.append(ei);

	img := display.newimage(((0,0),(260,30)), icon.chans, 0, draw->White);
	img.draw(icon.r, icon, ones, (280,55));
	ei = Element.icon(env, ((280,y2+55),(540,y2+85)), img, ones);
	ei.tag = "done.menu";
	el.append(ei);
	menu[j].nsel++;
	img = display.newimage(((0,0),(260,30)), icon.chans, 0, draw->White);
	img.draw(icon.r, icon, ones, (320,94));
	ei = Element.icon(env, ((320,y2+94),(580,y2+124)), img, ones);
	ei.tag = "main.menu";
	el.append(ei);
	menu[j].nsel++;

	if(el.r.max.y >= 480) {
		el.clip((el.r.min, (el.r.max.x, 480)));
	}
	cmpnd = Compound.box(env, (0,0), nil, el);
	return j;
}

makedone(ctxt: ref Context): int
{
	j: int;

	for (j=0; j<nmenu; j++)
		if (menu[j].tag == "done")
			break;
	if (j == nmenu) {
		nmenu++;
		menu[j].tag = "done";
	}
	menu[j].nsel = 1;
	menu[j].cursel = 0;

	mystyle := style;
	mystyle.highlightcolor = display.color(draw->White);
	mystyle.textcolor = display.color(draw->Black);

	icon := display.open(dir + "done.bit");
	mystyle.elemcolor = icon;
	env := ref Environ(ctxt.screen, ref mystyle);
	el := Element.elist(env, nil, Prefab->EVertical);
	ne := minutes(env, 25);
	ne.translate((395,270));
	ne.tag = "done";
	el.append(ne);
	ne = time(env, (289,414), 7, 37, pm);
	el.append(ne);
	el.clip(icon.r);
	cmpnd = Compound.box(env, (0,0), nil, el);
	return j;
}

minutes(env: ref Environ, m: int): ref Element
{
	icon := display.open(dir + sprint("%d.bit", m));
	return Element.icon(env, zr, icon, ones);
}

am: con int 0;
pm: con int 1;


time(env: ref Environ, p: Point, hr, min, ampm: int): ref Element
{
	ei := Element.elist(env, nil, Prefab->EHorizontal);
	ei.append(number(env, (0,0), hr, 1));
	ei.append(Element.text(env, ".", zr, Prefab->EText));
	ei.append(number(env, (0,0), min, 2));
	if (ampm == am)
		icon := display.open(dir + "AM.bit");
	else
		icon = display.open(dir + "PM.bit");
	ei.append(Element.icon(env, zr, icon, ones));
	ei.adjust(Prefab->Adjpack, Prefab->Adjleft);
	ei.translate(p);
	return ei;
}


digit(env: ref Environ, i: int): ref Element
{
	icon := display.open(dir + sprint("%d.bit", i));
	return Element.icon(env, zr, icon, ones);
}

number(env: ref Environ, p: Point, n: int, width: int): ref Element
{
	w := 0; x := 1;
	for (m:=n; m || w < width; m /= 10) { w++; x *= 10; }
	if (w == 0) w = 1;
	ei := Element.elist(env, nil, Prefab->EHorizontal);
	for (j := 0; j < w; j++) {
		x /= 10;
		ei.append(digit(env, n / x));
		n %= x;
	}
	ei.adjust(Prefab->Adjpack, Prefab->Adjleft);
	ei.translate(p);
	return ei;
}

keyshow(ctxt: ref Context, m, key: int): string
{
	sel := menu[m].cursel;
	case key {
	Ir->Select =>
		return nil;
	Ir->Enter =>
		return "done.menu";
	Ir->Zero or
	Ir->One or
	Ir->Two or
	Ir->Three or
	Ir->Four or
	Ir->Five or
	Ir->Six or
	Ir->Seven or
	Ir->Eight or
	Ir->Nine =>
		j := 0;
		for (o := order; o != nil; o = tl o) {
			item := hd o;
			if (j++ == sel) {
				item.n = key;
			}
			for (oo := item.subitem; oo != nil; oo = tl oo) {
				subitem := hd oo;
				if (j++ == sel) {
					subitem.n = key;
				}
			}
		}
		nil := makeshow(ctxt);
		cmpnd.draw();
		windows[0] = cmpnd.image;
		return nil;
	}
	return nil;
}

cmpnd:	ref Compound;

init(ctxt: ref Context, nil: list of string)
{
	key:	int;
	i:	int;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	prefab = load Prefab Prefab->PATH;
	mux = load Mux Mux->PATH;
	if ((bufio = load Bufio Bufio->PATH) == nil) {
		sys->print("Pizza: Can't load bufio\n");
		exit;
	}

	screen = ctxt.screen;
	display = ctxt.display;
	windows = array[3] of ref Image;

	ones = display.color(draw->White);
	zeroes = display.color(draw->Black);
	textfont := Font.open(display, "*default*");

	order = nil;

	zr = ((0, 0), (0, 0));

	red := display.color(draw->Red);
	yellow := display.color(draw->Yellow);
	black := display.color(draw->Black);
	white := display.color(draw->White);

	style = Style(
			textfont,	# titlefont
			textfont,	# textfont
			white,		# elemcolor
			black,		# edgecolor
			yellow,		# titlecolor	
			red,		# textcolor
			black);		# highlightcolor

	ctxt.ctomux <-= Mux->AMstartir;
	slavectl := chan of int;
	spawn topslave(ctxt.ctoappl, slavectl);

	tag := "main.menu";

	e: ref Element;
	m: int;
out:	for(;;) {
		m = makemenu(ctxt, tag);
	
		if (m < 0) {
			print("read menu: %r\n");
			break out;
		}
	
		cmpnd.draw();
		windows[0] = cmpnd.image;
sel:		for(;;) {
			(key, menu[m].cursel, e) =
				cmpnd.tagselect(cmpnd.contents, menu[m].cursel, ctxt.cir);
			if (e != nil && e.tag == "number") {
				if ((t := keyshow(ctxt, m, key)) != nil) {
					tag = t;
					break sel;
				}
				continue sel;
			}
			case key {
			Ir->Error =>
				continue sel;
			Ir->Select =>
				if (e == nil) break out;
				if (e.tag == "done") {
					print("exiting\n");
					break out;
				}
				if (e.tag == "done.menu") {
					tag = e.tag;
					break sel;
				}
				for (i=0; i<nmenu; i++) {
					if (menu[i].tag == e.tag) break;
				}
				if (i == nmenu) {
					print("%s not in menu\n", e.tag);
					break out;
				}
				if (len e.tag > 5 &&
				    e.tag[len e.tag -5:] == ".menu") {
					tag = e.tag;
					break sel;
				}
				if ((t := leafmenu(i)) != nil) {
					tag = t;
					break sel;
				}
				continue sel;
			Ir->Enter =>
				if (order == nil || tag == "done.menu")
					break out;
				tag = "show.menu";
				break sel;
			* =>
				;
			}
		}
	}
	slavectl <-= Mux->AMexit;
	ctxt.ctomux <-= Mux->AMexit;
}

topslave(ctoappl: chan of int, ctl: chan of int)
{
	m: int;

	for(;;) {
		alt{
		m = <-ctoappl =>
			if(m == Mux->MAtop) {
				screen.top(windows);
			}
		m = <-ctl =>
			return;
		}
	}
}

prices := array [47] of {
	("bufw10",	"Buffalo wings (10)",			 4.99, ""),
	("bufw24",	"Buffalo wings (24)",			 7.50, ""),
	("bufw48",	"Buffalo wings (48)",			13.50, ""),
	("breadst6",	"Bread sticks (6)",			 1.69, ""),
	("breadst6ch",	"Bread sticks with cheese (6)",		 2.59, ""),
	("breadst12",	"Bread sticks (12)",			 2.59, ""),
	("breadst12ch",	"Bread sticks with cheese (12)",	 4.59, ""),
	("antip",	"Antipasto",				 2.59, ""),
	("cole",	"Cole slaw",				 0.75, ""),
	("french",	"French fries",				 0.65, ""),
	("lg-coke",	"Large coke",				 1.25, ""),
	("lg-diet",	"Large diet coke",			 1.25, ""),
	("lg-root",	"Large root beer",			 1.25, ""),
	("lg-7-up",	"Large 7UP",				 1.25, ""),
	("md-coke",	"Medium coke",				 0.95, ""),
	("md-diet",	"Medium diet coke",			 0.95, ""),
	("md-root",	"Medium root beer",			 0.95, ""),
	("md-7-up",	"Medium 7UP",				 0.95, ""),
	("pan-large",	"Large pan pizza",			11.99,
		"panpizza-top.menu"),
	("pan-medium",	"Medium pan pizza",			 8.99,
		"panpizza-top.menu"),
	("pan-small",	"Small pan pizza",			 7.69,
		"panpizza-top.menu"),
	("sm-coke",	"Small coke",				 0.70, ""),
	("sm-diet",	"Small diet coke",			 0.70, ""),
	("sm-root",	"Small root beer",			 0.70, ""),
	("sm-7-up",	"Small 7UP",				 0.70, ""),
	("stuf-large",	"Stuffed pizza Grand Supreme",		 9.99,
		"stuffed-top.menu"),
	("stuf-medium",	"Stuffed crust specialty pizza",	11.99,
		"stuffed-top.menu"),
	("stuf-small",	"Stuffed cheese pizza",			 9.99,
		"stuffed-top.menu"),
	("thin-large",	"Large thin'n'crispy piza",		11.99,
		"thincrisp-top.menu"),
	("thin-medium",	"Medium thin'n'crispy pizza",		 8.99,
		"thincrisp-top.menu"),
	("thin-small",	"Small thin'n'crispy pizza",		 7.69,
		"thincrisp-top.menu"),
	("top-anc",	"anchovies",				 0.00, ""),
	("top-art",	"artichoke",				 0.00, ""),
	("top-bac",	"bacon",				 0.00, ""),
	("top-bee",	"beef",					 0.00, ""),
	("top-ext",	"extra cheese",				 0.00, ""),
	("top-gre",	"green peppers",			 0.00, ""),
	("top-ham",	"ham",					 0.00, ""),
	("top-ita",	"italian sausage",			 0.00, ""),
	("top-jal",	"jalapi sausage",			 0.00, ""),
	("top-jal",	"jalapinoo",				 0.00, ""),
	("top-mus",	"mushroom",				 0.00, ""),
	("top-oli",	"black olive",				 0.00, ""),
	("top-oni",	"onion",				 0.00, ""),
	("top-pep",	"pepperoni",				 0.00, ""),
	("top-por",	"pork",					 0.00, ""),
	("youchoose",	"Surprise menu",			13.99, "")
};

pricelist(tag: string): (string, real, string)
{
	n, s:	string;
	p:	real;
	t := "";

	for (i := 0; i < len prices; i++) {
		(t, n, p, s) = prices[i];
		if (t == tag) break;
	}
	if (i == len prices) {
		print("Terrible bug\n");
		return ("", 0.0, "");
	}
	return (n, p, s);
}

Subitem: adt {
	tag:	string;
	n:	int;
	item:	string;
	price:	real;
	total:	real;
};

Item: adt {
	tag:	string;
	n:	int;
	item:	string;
	price:	real;
	total:	real;
	subitem:list of ref Subitem;
};

order: list of ref Item;
curitem: ref Item;

leafmenu(m: int): string
{
	tag := menu[m].tag;
	(itemname, price, next) := pricelist(tag);
	case (tag) {
	"pan-large" or
	"pan-medium" or
	"pan-small" or
	"stuf-large" or
	"stuf-medium" or
	"stuf-small" or
	"thin-large" or
	"thin-medium" or
	"thin-small" =>
		curitem = ref  Item(tag, 1, itemname, price, 0.0, nil);
		order = curitem :: order;
		return next;
	"youchoose" =>
		curitem = ref  Item(tag, 1, itemname, price, 0.0, nil);
		order = curitem :: order;
	"top-anc" or
	"top-art" or
	"top-bac" or
	"top-bee" or
	"top-ext" or
	"top-gre" or
	"top-ham" or
	"top-ita" or
	"top-jal" or
	"top-mus" or
	"top-oli" or
	"top-oni" or
	"top-pep" or
	"top-por" =>
		if (curitem == nil) return nil;

		case (curitem.tag) {
		"pan-large" or
		"thin-large" =>
			price = 1.50;
		"thin-medium" or
		"pan-medium" =>
			price = 1.00;
		"pan-small" or
		"thin-small" =>
			price = 0.50;
		"stuf-large" or
		"stuf-medium" or
		"stuf-small" =>
			# Only one topping for stuffed pizzas
			curitem.subitem = nil;
			price = 0.0;
		}

		for (si := curitem.subitem; si != nil; si = tl si)
			if ((hd si).tag == tag) {
				(hd si).n++;
				break;
			}
		if (si == nil) {
			curitem.subitem =
				ref Subitem(tag, 1, itemname, price, 0.0) ::
					curitem.subitem;
		}
	* =>
		for (item := order; item != nil; item = tl item)
			if ((hd item).tag == tag) {
				curitem = hd item;
				(hd item).n++;
				break;
			}
		if (item == nil) {
			curitem = ref  Item(tag, 1, itemname, price, 0.0, nil);
			order = curitem :: order;
		}
	}
	return nil;
}
