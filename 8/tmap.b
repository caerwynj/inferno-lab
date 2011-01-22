implement Tmap;
include "sys.m";
	sys: Sys;
	print, sprint: import sys;
include "draw.m";
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "tkclient.m";
	tkclient: Tkclient;
include "math.m";
	math: Math;
	log, sqrt, Infinity, fmax: import math;
include "arg.m";
	arg: Arg;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "treemap.m";
	treemap: Treemap;
	Rect, Item, slice, square, strip, btree: import treemap;

Tmap: module
{
	init:	fn(ctxt: ref Draw->Context, nil: list of string);
};

gr_cfg := array[] of {
	"frame .fc",
	"frame .fc.b",
	"label .fc.b.xy -text {0 0} -anchor e",
	"pack .fc.b.xy -fill x",
	"pack .fc.b -fill both -expand 1",
	"canvas .fc.c -relief sunken -bd 2 -width 800 -height 800 -bg white"+
		" -font /fonts/lucidasans/unicode.8.font",
	"pack .fc.c -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .fc -fill both -expand 1",
	"pack propagate . 0",
	"bind .fc.c <ButtonPress-1> {send grcmd down1,%x,%y}",
	"bind .fc.c <ButtonPress-2> {send grcmd down2,%x,%y}",
	"bind .fc.c <ButtonPress-3> {send grcmd down3,%x,%y}",
};

TkCmd(t: ref Toplevel, arg: string): string
{
	rv := tk->cmd(t,arg);
	if(rv!=nil && rv[0]=='!')
		print("tk->cmd(%s): %s\n",arg,rv);
	return rv;
}

rootstk: list of ref Item;
root: ref Item;
format := 0;
maxdepth := 0;

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	arg = load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	treemap = load Treemap Treemap->PATH;
	treemap->init();
	arg->init(argv);
	while((c := arg->opt()) != 0)
		case c{
		'1'	=> format = 1;
		'2'	=> format = 2;
		'3' 	=> format = 3;
		* => sys->print("unkown option (%c)\n", c);
		}
	argv = arg->argv();
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	tkclient->init();
	(t, tb) := tkclient->toplevel(ctxt, "", "Treemap", Tkclient->Appl);
	cc := chan of string;
	tk->namechan(t, cc, "grcmd");
	for (i:=0; i<len gr_cfg; i++)
		tk->cmd(t,gr_cfg[i]);
	tkclient->onscreen(t, nil);
	tkclient->startinput(t, "kbd"::"ptr"::nil);
#	math->FPcontrol(0, math->INVAL|math->OVFL|math->UNFL|math->ZDIV);
	n := 0;
	maxn := 100;
	items := array[maxn] of ref Item;
	tot := 0.0;
	root  = ref Item(0.0, Rect(5.0, 5.0, 790.0, 790.0), 0, 0, "", nil,nil);
	iobuf: ref Iobuf;
	if(argv != nil)
		iobuf = bufio->open(hd argv, bufio->OREAD);
	else
		iobuf = bufio->fopen(sys->fildes(0), bufio->OREAD);
	while((line := iobuf.gets('\n')) != nil){
		line = line[0:len line - 1];
		(nf, fld) := sys->tokenize(line, " \t\n\r");
		if(nf != 2)
			continue;
		y := real hd fld;
		nm := hd tl fld;
		if(nm == "."  || nm == "/" || y == 0.0)
			continue;
		putfile(ref Item(y, Rect(.0,.0,1.0,1.0), 0, 0, nm, nil, nil));
		n++;
		tot += y;
	}
	root.size = total(root);
#	maxdepth = mdepth(root, 0);
	layout(root);
#	dump(root);
	draw(root, t, len dc - 1);
	path: list of ref Item;
	tagid: list of string;
	tagid = nil;
	cmdloop: for(;;) alt {
	s := <-t.ctxt.kbd =>
		tk->keyboard(t, s);
	s := <-t.ctxt.ptr =>
		tk->pointer(t, *s);
	s := <-t.ctxt.ctl or
	s = <-t.wreq or
	s = <-tb =>
		if(s == "exit")
			break cmdloop;
		tkclient->wmctl(t, s);
		case s{
		"size" =>
			canvw := int TkCmd(t, ".fc.c cget -width");
			canvh := int TkCmd(t, ".fc.c cget -height");
			TkCmd(t,".fc.b.xy configure -text {"+sprint("%d %d",canvw,canvh)+"}");
		}
	press := <-cc =>
		(nn,cmds) := sys->tokenize(press,",");
		if(cmds==nil) continue;
		case hd cmds {
		"down1" =>
			xpos := real(hd tl cmds);
			ypos := real(hd tl tl cmds);
			x := xpos;
			y := ypos;
			path = treemap->getpath(root, x, y);
			for(tag:=tagid; tag!= nil; tag=tl tag)
				TkCmd(t, sprint(".fc.c delete %s", (hd tag)));
			tagid = nil;
			if(path == nil){
				TkCmd(t,".fc.b.xy configure -text {"+sprint("%.3g %.3g",x,y)+"}");
			}else{
				s := "";
				item: ref Item;
				for(g:=path; g!=nil; g=tl g){
					item = (hd g);
					r := item.bounds;
					s +=  sprint("%s %g ", item.name, item.size);
					tg := TkCmd(t, sprint(".fc.c create rectangle %.1f %.1f %.1f %.1f  -outline red*0.5 -width 5.0", 
						r.x, r.y, r.x+r.w, r.y+r.h));
					tagid = tg :: tagid;
				}
				TkCmd(t,".fc.b.xy configure -text {"+s+"}");
			}
		"down2" =>
			xpos := real(hd tl cmds);
			ypos := real(hd tl tl cmds);
			x := xpos;
			y := ypos;
			path = treemap->getpath(root, x, y);
			for(tag:=tagid; tag!= nil; tag=tl tag)
				TkCmd(t, sprint(".fc.c delete %s", (hd tag)));
			tagid = nil;
			if(path == nil){
				TkCmd(t,".fc.b.xy configure -text {"+sprint("%.3g %.3g",x,y)+"}");
			}else {
				item := tl path;
				if(item != nil){
					rootstk = root :: rootstk;
					root = hd item;
					root.bounds = Rect(5.0, 5.0, 790.0, 790.0);
					layout(root);
					TkCmd(t, ".fc.c delete all");
					draw(root, t, len dc - 1);
				}
			}
		"down3" =>
			if(rootstk != nil){
				root = hd rootstk;
				rootstk = tl rootstk;
				layout(root);
				TkCmd(t, ".fc.c delete all");
				draw(root, t, len dc - 1);
			}
		}
	}
	TkCmd(t,"destroy .;update");
	t = nil;
}

layout(f: ref Item)
{
	if(f.children == nil)
		return;
	items:=array[len f.children] of ref Item;
	i:=0;
	for(g:=f.children; g!=nil; g = tl g)
		items[i++] = hd g;
	case format {
	0	=>
		btree(items[0:i], f.bounds, treemap->VERTICAL);
	1	=>
		slice(items[0:i], f.bounds, treemap->HORIZONTAL, treemap->ASCENDING);
	2	=>
		square(items[0:i], f.bounds);
	3	=>
		strip(items[0:i], f.bounds);
	}
	for(g=f.children; g!=nil; g = tl g)
		layout(hd g);
}

#dc := array[] of {"maroon", "red", "teal", "aqua", "green", "lime",  "orange" , "yellow"};
#dc := array[] of {"004400", "005500", "006600", "007700", 
#	"448844", "4C994C", "55AA55", "5DBB5D", 
#	"88CC88", "93DD93", "9EEE9E", "AAFFAA"};
dc := array[] of {"FF0000", "FF5500", "FFAA00",
	"CCCC00", "BBBB00", "AAAA55",
	"5DBB5D", "55AAAA",  "4993DD", 
	"0000DD", "0000AA", "000077"};
	
dlw := array[] of {0.1, 0.1, 0.1,
	0.1, 0.25, 0.25, 
	0.5, 0.75, 0.80, 
	1.0, 1.0, 1.0};

draw(f: ref Item, t: ref Toplevel, depth: int)
{
	if(depth<0)
		depth=0;
	for(g:=f.children; g !=nil; g = tl g){
		r := (hd g).bounds;
		if(0)
			sys->print("%g %g %g %g\n", r.x, r.y, r.x+r.w, r.y+r.h);
		TkCmd(t, sprint(".fc.c create rectangle %.1f %.1f %.1f %.1f  -fill #%s -outline black -width %.2f", 
				r.x, r.y, r.x+r.w, r.y+r.h, dc[depth],  dlw[depth]));
		draw(hd g, t, depth-1);
	}
}

split(s: string): (string, string)
{
	for(i := 0; i < len s; i++)
		if(s[i] == '/'){
			for(j := i+1; j < len s && s[j] == '/';)
				j++;
			return (s[0:i], s[j:]);
		}
	return (nil, s);
}

putfile(f: ref Item)
{
	while(f.name[0] == '/')
		f.name = f.name[1:];
	n := f.name;
	df := root;
	for(;;){
		(d, rest) := split(n);
		if(d == nil || rest == nil){
			f.name = n;
			break;
		}
		g := df.find(d);
		if(g == nil){
			g = ref *f;
			g.name = d;
			df.enter(g);
		}
		n = rest;
		df = g;
	}
	df.enter(f);
}

mdepth(f: ref Item, depth: int): int
{
	max := 0;
	if(f.children == nil)
		return depth +1;
	for(g:=f.children; g != nil; g = tl g){
		d := mdepth(hd g, depth);
		if(d > max)
			max = d;
	}
	return max;
}

total(f: ref Item): real
{
	if(f.children == nil)
		return f.size;
	tot := 0.0;
	for(g:=f.children; g !=nil; g = tl g)
		tot += total(hd g);
	f.size = tot;
	return tot;
}

dump(f: ref Item)
{
	print("%s %.3f %.3f %.3f %.3f %.3f\n", f.name, f.size, f.bounds.x, f.bounds.y, f.bounds.w, f.bounds.h);
	for(g:=f.children; g!=nil; g=tl g){
		dump(hd g);
	}
}
