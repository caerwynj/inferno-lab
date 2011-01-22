implement Brutusext;

Name:	con "Brutus Graph";

include "sys.m";
	sys: Sys;
	print, sprint: import sys;

include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
	Toplevel: import tk;
include "math.m";
	math: Math;
	ceil, fabs, floor, Infinity, log10, pow10, sqrt: import math;

include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

include	"tkclient.m";
	tkclient: Tkclient;

include	"brutus.m";
include	"brutusext.m";

stderr: ref Sys->FD;

	OP: adt{
		code, n: int;
		x, y: array of real;
		t: string;
	};

	Plot: adt{
		bye:	fn(p: self ref Plot);
		equalxy:fn(p: self ref Plot);
		graph:	fn(p: self ref Plot, x, y: array of real);
		paint: 	fn(p: self ref Plot, xlabel, xunit, ylabel, yunit: string);
		pen:	fn(p: self ref Plot, nib: int);
		text:	fn(p: self ref Plot, justify: int, s: string, x, y: real);

		op: list of OP;
		xmin, xmax, ymin, ymax: real;
		textsize: real;
		t: ref Tk->Toplevel;		# window containing .fc.c canvas
		titlechan: chan of string;	# Wm titlebar
		canvaschan: chan of string;	# button clicks for measurements
	};

	# op code
	GRAPH:		con 1;
	TEXT:		con 2;
	PEN:		con 3;

	# pen
	CIRCLE:		con 101;
	CROSS:		con 102;
	SOLID:		con 103;
	DASHED:		con 104;
	INVIS:		con 105;
	REFERENCE:	con 106;
	DOTTED:		con 107;

	# text justify
	LJUST:		con 8r00;
	CENTER:		con 8r01;
	RJUST:		con 8r02;
	HIGH:		con 8r00;
	MED:		con 8r10;
	BASE:		con 8r20;
	LOW:		con 8r30;
	UP:		con 8r100;

gr_cfg := array[] of {
	"frame %s",
	"frame %s.b",
	"label %s.b.xy -text {0 0} -anchor e",
	"pack %s.b.xy -fill x",
	"pack %s.b -fill both -expand 1",
	"canvas %s.c -relief ridge -bd 1 -width 600 -height 480 -bg white"+
		" -font /fonts/lucidasans/unicode.8.font",
	"pack %s.c -fill both -expand 1",
#	"pack .fc -fill both -expand 1",
#	"pack propagate . 0",
	"bind %s.c <ButtonPress-1> {send grcmd down1,%x,%y}",
};

cook(nil: string, nil: int, nil: string): (ref Brutusext->Celem, string)
{	return (nil, nil);
}

init(s: Sys, d: Draw, b: Bufio, t: Tk, w: Tkclient)
{
	sys = s;
	draw = d;
	bufio = b;
	tk = t;
	tkclient = w;
	math = load Math Math->PATH;
	stderr = sys->fildes(2);
}

canvas := ".fc.c";
frame := ".fc";
create(nil: string, t: ref Tk->Toplevel, name, args: string): string
{
	display := t.image.display;
	filename := args;
	textsize := 8.;	# textsize is in points, if no user transform
	cc := chan of string;
	channame := name + "grcmd";
	tk->namechan(t, cc, channame);
	p := ref Plot(nil, Infinity,-Infinity,Infinity,-Infinity, textsize, t, nil, cc);
	canvas = name + ".c";
	frame = name;
#	for (i:=0; i<len gr_cfg; i++)
#		tk->cmd(p.t,sprint(gr_cfg[i], canvas));
	tk->cmd(p.t,sprint("frame %s", name));
	tk->cmd(p.t,sprint("frame %s.b", name));
	tk->cmd(p.t,sprint("label %s.b.xy -text {0 0} -anchor e", name));
	tk->cmd(p.t,sprint("pack %s.b.xy -fill x", name));
	tk->cmd(p.t,sprint("pack %s.b -fill both -expand 1", name));
	tk->cmd(p.t,sprint("canvas %s.c -relief ridge -bd 1 -width 600 -height 480 -bg white"+
		" -font /fonts/lucidasans/unicode.8.font", name));
	tk->cmd(p.t,sprint("pack %s.c -fill both -expand 1", name));
	tk->cmd(p.t,sprint("bind %s.c <ButtonPress-1> {send %s down1,%%x,%%y}", name, channame));
#	tk->cmd(p.t, sprint("canvas %s -relief ridge -bd 1 -width 600 -height 480 -bg white -font /fonts/lucidasans/unicode.8.font", canvas));
	input := bufio->open(filename,bufio->OREAD);
	if(input==nil){
		print("can't read %s",filename);
		exit;
	}

	n := 0;
	maxn := 100;
	x := array[maxn] of real;
	y := array[maxn] of real;
	while(1){
		xn := input.gett(" \t\n\r");
		if(xn==nil)
			break;
		yn := input.gett(" \t\n\r");
		if(yn==nil){
			print("after reading %d pairs, saw singleton\n",n);
			exit;
		}
		if(n>=maxn){
			maxn *= 2;
			newx := array[maxn] of real;
			newy := array[maxn] of real;
			for(i:=0; i<n; i++){
				newx[i] = x[i];
				newy[i] = y[i];
			}
			x = newx;
			y = newy;
		}
		x[n] = real xn;
		y[n] = real yn;
		n++;
	}
	if(n==0){
		print("empty input\n");
		exit;
	}

	p.graph(x[0:n],y[0:n]);
	p.pen(CIRCLE);
	p.graph(x[0:n],y[0:n]);
	p.paint("",nil,"",nil);
	spawn	p.bye();
	return "";
}

TkCmd(t: ref Toplevel, arg: string): string
{
	rv := tk->cmd(t,arg);
	if(rv!=nil && rv[0]=='!')
		print("tk->cmd(%s): %s\n",arg,rv);
	return rv;
}


Plot.bye(p: self ref Plot)
{
	for(;;) alt {
	press := <-p.canvaschan =>
		(n,cmds) := sys->tokenize(press,",");
		if(cmds==nil) continue;
		case hd cmds {
		"down1" =>
			xpos := real(hd tl cmds);
			ypos := real(hd tl tl cmds);
			x := (xpos-bx)/ax;
			y := -(ypos-tky+by)/ay;
			TkCmd(p.t,sprint("%s.b.xy configure -text {%.3g %.3g}", frame, x,y));
		}
	}
}

Plot.equalxy(p: self ref Plot)
{
	r := 0.;
	if( r < p.xmax - p.xmin ) r = p.xmax - p.xmin;
	if( r < p.ymax - p.ymin ) r = p.ymax - p.ymin;
	m := (p.xmax + p.xmin)/2.;
	p.xmax = m + r/2.;
	p.xmin = m - r/2.;
	m = (p.ymax + p.ymin)/2.;
	p.ymax = m + r/2.;
	p.ymin = m - r/2.;
}

Plot.graph(p: self ref Plot, x, y: array of real)
{
	n := len x;
	op := OP(GRAPH, n, array[n] of real, array[n] of real, nil);
	while(n--){
		t := x[n];
		op.x[n] = t;
		if(t < p.xmin) 
			p.xmin = t;
		if(t > p.xmax) 
			p.xmax = t;
		t = y[n];
		op.y[n] = t;
		if(t < p.ymin) 
			p.ymin = t;
		if(t > p.ymax) 
			p.ymax = t;
	}
	p.op = op :: p.op;
}

Plot.text(p: self ref Plot, justify: int, s: string, x, y: real)
{
	op := OP(TEXT, justify, array[1] of real, array[1] of real, s);
	op.x[0] = x;
	op.y[0] = y;
	p.op = op :: p.op;
}

Plot.pen(p: self ref Plot, nib: int)
{
	p.op = OP(PEN, nib, nil, nil, nil) :: p.op;
}


#---------------------------------------------------------
# The rest of this file is concerned with sending the "display list"
# to Tk.  The only interesting parts of the problem are picking axes
# and drawing dashed lines properly.

ax, bx, ay, by: real;			# transform user to pixels
tky: con 630.;				# Tk_y = tky - y
nseg: int;				# how many segments in current stroke path
pendown: int;				# is pen currently drawing?
xoff := array[] of{"w","","e"};	# LJUST, CENTER, RJUST
yoff := array[] of{"n","","s","s"};	# HIGH, MED, BASE, LOW
linewidth: real;
toplevel: ref Toplevel;			# p.t
tkcmd: string;

mv(x, y: real)
{
	tkcmd = sprint("%s create line %.1f %.1f", canvas, ax*x+bx, tky-(ay*y+by));
}

stroke()
{
	if(pendown){
		tkcmd += " -width 3";   # -capstyle round -joinstyle round
		TkCmd(toplevel,tkcmd);
		tkcmd = nil;
		pendown = 0;
		nseg = 0;
	}
}

vec(x, y: real)
{
	tkcmd += sprint(" %.1f %.1f", ax*x+bx, tky-(ay*y+by));
	pendown = 1;
	nseg++;
	if(nseg>1000){
		stroke();
		mv(x,y);
	}
}

circle(u, v, radius: real)
{
	x := ax*u+bx;
	y := tky-(ay*v+by);
	r := radius*(ax+ay)/2.;
	tkcmd = sprint("%s create oval %.1f %.1f %.1f %.1f -width 3", canvas,
		x-r, y-r, x+r, y+r);
	TkCmd(toplevel,tkcmd);
	tkcmd = nil;
}

text(s: string, x, y: real, xoff, yoff: string)
{
	# rot = rotation in degrees.  90 is used for y-axis
	# x,y are in PostScript coordinate system, not user
	anchor := yoff + xoff;
	if(anchor!="")
		anchor = "-anchor " + anchor + " ";
	tkcmd = sprint("%s create text %.1f %.1f %s-text '%s", canvas,
		ax*x+bx,
		tky-(ay*y+by), anchor, s);
	TkCmd(toplevel,tkcmd);
	tkcmd = nil;
}

datarange(xmin, xmax, margin: real): (real,real)
{
	r := 1.e-30;
	if( r < 0.001*fabs(xmin) ) 
		r = 0.001*fabs(xmin);
	if( r < 0.001*fabs(xmax) ) 
		r = 0.001*fabs(xmax);
	if( r < xmax-xmin ) 
		r = xmax-xmin;
	r *= 1.+2.*margin;
	x0 :=(xmin+xmax)/2. - r/2.;
	return ( x0, x0 + r);
}

dashed(ndash: int, x, y: array of real)
{
	cx, cy: real;	# current position
	d: real;	# length undone in p[i],p[i+1]
	t: real;	# length undone in current dash
	n := len x;
	if(n!=len y || n<=0)
		return;

	# choose precise dashlen
	s := 0.;
	for(i := 0; i < n - 1; i += 1){
		u := x[i+1] - x[i];
		v := y[i+1] - y[i];
		s += sqrt(u*u + v*v);
	}
	i = int floor(real ndash * s);
	if(i < 2) 
		i = 2;
	dashlen := s / real(2 * i - 1);

	t = dashlen;
	ink := 1;
	mv(x[0], y[0]);
	cx = x[0];
	cy = y[0];
	for(i = 0; i < n - 1; i += 1){
		u := x[i+1] - x[i];
		v := y[i+1] - y[i];
		d = sqrt(u * u + v * v);
		if(d > 0.){
			u /= d;
			v /= d;
			while(t <= d){
				cx += t * u;
				cy += t * v;
				if(ink){
					vec(cx, cy);
					stroke();
				}else{
					mv(cx, cy);
				}
				d -= t;
				t = dashlen;
				ink = 1 - ink;
			}
			cx = x[i+1];
			cy = y[i+1];
			if(ink){
				vec(cx, cy);
			}else{
				mv(cx, cy);
			}
			t -= d;
		}
	}
	stroke();
}

labfmt(x:real): string
{
	lab := sprint("%.6g",x);
	if(len lab>2){
		if(lab[0]=='0' && lab[1]=='.')
			lab = lab[1:];
		else if(lab[0]=='-' && len lab>3 && lab[1]=='0' && lab[2]=='.')
			lab = "-"+lab[2:];
	}
	return lab;
}

Plot.paint(p: self ref Plot, xlabel, xunit, ylabel, yunit: string)
{
	oplist: list of OP;

	# tunable parameters for dimensions of graph (fraction of box side)
	margin: con 0.075;		# separation of data from box boundary
	ticksize := 0.02;
	sep := ticksize;		# separation of text from box boundary

	# derived coordinates of various feature points...
	x0, x1, y0, y1: real;		# box corners, in original coord
	# radius := 0.2*p.textsize;	# radius for circle marker
	radius := 0.8*p.textsize;	# radius for circle marker

	Pen := SOLID;
	width := SOLID;
	linewidth = 2.;
	nseg = 0;
	pendown = 0;

	if(xunit=="") xunit = nil;
	if(yunit=="") yunit = nil;

	(x0,x1) = datarange(p.xmin,p.xmax,margin);
	ax = (400.-2.*p.textsize)/((x1-x0)*(1.+2.*sep));
	bx = 506.-ax*x1;
	(y0,y1) = datarange(p.ymin,p.ymax,margin);
	ay = (400.-2.*p.textsize)/((y1-y0)*(1.+2.*sep));
	by = 596.-ay*y1;
	# PostScript version
	# magic numbers here come from BoundingBox: 106 196 506 596
	# (x0,x1) = datarange(p.xmin,p.xmax,margin);
	# ax = (400.-2.*p.textsize)/((x1-x0)*(1.+2.*sep));
	# bx = 506.-ax*x1;
	# (y0,y1) = datarange(p.ymin,p.ymax,margin);
	# ay = (400.-2.*p.textsize)/((y1-y0)*(1.+2.*sep));
	# by = 596.-ay*y1;

	# convert from fraction of box to PostScript units
	ticksize *= ax*(x1-x0);
	sep *= ax*(x1-x0);

	# revert to original drawing order
	log := p.op;
	oplist = nil;
	while(log!=nil){
		oplist = hd log :: oplist;
		log = tl log;
	}
	p.op = oplist;

	toplevel = p.t;
	nop := 0;
	#------------send display list to Tk-----------------
	while(oplist!=nil){
		op := hd oplist;
		n := op.n;
		case op.code{
		GRAPH =>
			if(Pen == DASHED){
				dashed(17, op.x, op.y);
			}else if(Pen == DOTTED){
				dashed(85, op.x, op.y);
			}else{
				for(i:=0; i<n; i++){
					xx := op.x[i];
					yy := op.y[i];
					if(Pen == CIRCLE){
						circle(xx, yy, radius/(ax+ay));
					}else if(Pen == CROSS){
						mv(xx-radius/ax, yy);
						vec(xx+radius/ax, yy);
						stroke();
						mv(xx, yy-radius/ay);
						vec(xx, yy+radius/ay);
						stroke();
					}else if(Pen == INVIS){
					}else{
						if(i==0){
							mv(xx, yy);
						}else{
							vec(xx, yy);
						}
					}
				}
				stroke();
			}
		TEXT =>
			angle := 0.;
			if(op.n&UP) angle = 90.;
			text(op.t,op.x[0],op.y[0],xoff[n&7],yoff[(n>>3)&7]);
		PEN =>
			Pen = n;
			if( Pen==SOLID && width!=SOLID ){
				linewidth = 2.;
				width=SOLID;
			}else if( Pen==REFERENCE && width!=REFERENCE ){
				linewidth = 0.8;
				width=REFERENCE;
			}
		}
		oplist = tl oplist;
	}

	#--------------------now add axes-----------------------
	mv(x0,y0);
	vec(x1,y0);
	vec(x1,y1);
	vec(x0,y1);
	vec(x0,y0);
	stroke();

	# x ticks
	(lab1,labn,labinc,k,u,s) := mytic(x0,x1);
	for (i := lab1; i <= labn; i += labinc){
		r := real i*s*u;
		mv(r,y0);
		vec(r,y0+ticksize/ay);
		stroke();
		mv(r,y1);
		vec(r,y1-ticksize/ay);
		stroke();
		text(labfmt(real i*s),r,y0-sep/ay,"","n");
	}
	yy := y0-(2.*sep+p.textsize)/ay;
	labelstr := "";
	if(xlabel!=nil)
		labelstr = xlabel;
	if(k!=0||xunit!=nil)
		labelstr += " /";
	if(k!=0)
		labelstr += " ₁₀"+ string k;
	if(xunit!=nil)
		labelstr += " " + xunit;
	text(labelstr,(x0+x1)/2.,yy,"","n");

	# y ticks
	(lab1,labn,labinc,k,u,s) = mytic(y0,y1);
	for (i = lab1; i <= labn; i += labinc){
		r := real i*s*u;
		mv(x0,r);
		vec(x0+ticksize/ax,r);
		stroke();
		mv(x1,r);
		vec(x1-ticksize/ax,r);
		stroke();
		text(labfmt(real i*s),x0-sep/ax,r,"e","");
	}
	xx := x0-(4.*sep+p.textsize)/ax;
	labelstr = "";
	if(ylabel!=nil)
		labelstr = ylabel;
	if(k!=0||yunit!=nil)
		labelstr += " /";
	if(k!=0)
		labelstr += " ₁₀"+ string k;
	if(yunit!=nil)
		labelstr += " " + yunit;
	text(labelstr,xx,(y0+y1)/2.,"e","");

	TkCmd(p.t, "update");
}



# automatic tic choice                      Eric Grosse  9 Dec 84
# Input: low and high endpoints of expanded data range
# Output: lab1, labn, labinc, k, u, s   where the tics are
#   (lab1*s, (lab1+labinc)*s, ..., labn*s) * 10^k
# and u = 10^k.  k is metric, i.e. k=0 mod 3.

max3(a, b, c: real): real
{
	if(a<b) a=b;
	if(a<c) a=c;
	return(a);
}

my_mod(i, n: int): int
{
	while(i< 0) i+=n;
	while(i>=n) i-=n;
	return(i);
}

mytic(l, h: real): (int,int,int,int,real,real)
{
	lab1, labn, labinc, k, nlab, j, ndig, t1, tn: int;
	u, s: real;
	eps := .0001;
	k = int floor( log10((h-l)/(3.+eps)) );
	u = pow10(k);
	t1 = int ceil(l/u-eps);
	tn = int floor(h/u+eps);
	lab1 = t1;
	labn = tn;
	labinc = 1;
	nlab = labn - lab1 + 1;
	if( nlab>5 ){
		lab1 = t1 + my_mod(-t1,2);
		labn = tn - my_mod( tn,2);
		labinc = 2;
		nlab = (labn-lab1)/labinc + 1;
		if( nlab>5 ){
			lab1 = t1 + my_mod(-t1,5);
			labn = tn - my_mod( tn,5);
			labinc = 5;
			nlab = (labn-lab1)/labinc + 1;
			if( nlab>5 ){
				u *= 10.; 
				k++;
				lab1 = int ceil(l/u-eps);
				labn = int floor(h/u+eps);
				nlab = labn - lab1 + 1;
				labinc = 1;
			} else if( nlab<3 ){
				lab1 = t1 + my_mod(-t1,4);
				labn = tn - my_mod( tn,4);
				labinc = 4;
				nlab = (labn-lab1)/labinc + 1;
			}
		}
	}
	ndig = int(1.+floor(log10(max3(fabs(real lab1),fabs(real labn),1.e-30))));
	if( ((k<=0)&&(k>=-ndig))   # no zeros have to be added
	    || ((k<0)&&(k>=-3))
	    || ((k>0)&&(ndig+k<=4)) ){   # even with zeros, label is small
		s = u;
		k = 0;
		u = 1.;
	}else if(k>0){
		s = 1.;
		j = ndig;
		while(k%3!=0){ 
			k--; 
			u/=10.; 
			s*=10.; 
			j++; 
		}
		if(j-3>0){ 
			k+=3; 
			u*=1000.; 
			s/=1000.; 
		}
	}else{ # k<0
		s = 1.;
		j = ndig;
		while(k%3!=0){ 
			k++; 
			u*=10.; 
			s/=10.; 
			j--; 
		}
		if(j<0){ 
			k-=3; 
			u/=1000.; 
			s*=1000.; 
		}
	}
	return (lab1, labn, labinc, k, u, s);
}
