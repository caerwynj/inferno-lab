implement Popi;

# From the original popi of the book Beyond Photography - The Digital Darkroom
# By Gerard J. Holzmann
#	Copyright (c) 1988 by Bell Telephone Laboratories, Incorporated.
#
# Permission to use is granted provided that credit is given to the original
# source, and the copyright (1988) of AT&T Bell Laboratories is mentioned
# in revisions and extensions of the original code.


include "draw.m";
	draw: Draw;
	Rect, Display, Screen, Image, Point: import draw;
include "sys.m";
	sys: Sys;
	fildes, fprint, print: import sys;
include "math.m";
	math: Math;
	atan2, hypot, sin, pow, sqrt, cos, atan, log: import math;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "libc.m";
	libc: Libc;
	isalpha, isdigit: import  libc;
include "rand.m";
	rand: Rand;
include "arg.m";
	arg: Arg;
include "tk.m";
	tk: Tk;
include "tkclient.m";
	tkclient: Tkclient;

noerr: int;
DEF_X: con 248;
DEF_Y: con 248;
MANY: con 128;
Zmax: con 255;
RVAL, LVAL, FNAME, VALUE, NAME, 
NEW, OLD, AND, OR, EQ, NE, GE, LE, 
UMIN, POW, SIN, COS, ATAN, SQRT, LOG, ABS: con 257+iota;

SRC: adt{
	pix: array of array of int;	#  pix[y][x] 
	str: string;
};

parsed := array[MANY] of int;
src := array[MANY] of ref SRC;
CUROLD: int = 0;
CURNEW: int = 1;
lexval: int;
prs: int = 0;
nsrc: int = 2;
text : string;
io : ref Iobuf;
ctxt: ref Draw->Context;
eflag: string;

Popi: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ct: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	libc = load Libc Libc->PATH;
	rand = load Rand Rand->PATH;
	draw= load Draw Draw->PATH;
	arg = load Arg Arg->PATH;
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;
	
	ctxt = ct;
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	arg->init(argv);
	while((c := arg->opt()) != 0)	
		case c {
		'e' => eflag = arg->earg();
		* => sys->print("unknown option (%c\n", c);
		}
	argv = arg->argv();
	i: int;
	if(eflag == nil)
		io = bufio->fopen(sys->fildes(0), bufio->OREAD);
	else
		io = bufio->sopen(eflag);

	for(i = 0; i < MANY; i++)
		src[i] = ref SRC;
	src[CUROLD].pix = array[DEF_Y] of array of int;
	src[CURNEW].pix = array[DEF_Y] of array of int;
	for(i = 0; i < DEF_Y; i++){
		src[CUROLD].pix[i] = array[DEF_X] of {* => 0};
		src[CURNEW].pix[i] = array[DEF_X] of {* => 0};
	}
	mkpolar();
	for(; argv != nil; argv = tl argv)
		getpix(src[nsrc], hd argv);
	tkclient->init();
	img := chan of ref Image;
	spawn viewer(img);
	reader(img);
}

parse(): int
{
#	sys->print("-> ");
	while(noerr)
		case(lat = lex()){
		'q' =>
			return  0;
		'\n' =>
			return  1;
		';' =>
			;
		'f' =>
			showfiles();
		'r' =>
			getname();
			if(!noerr)
				continue;
			getpix(src[nsrc], text);
		'w' =>
			getname();
			if(!noerr)
				continue;
			putpix(src[CUROLD], text);
		#  example of adding a function defined in lib.c 
		'u' =>
			getname();
			case text {
			"slicer" =>
				slicer();
			"oil" =>
				oil();
			"matte" =>
				matte();
			"shear" =>
				shear();
			"tiling" =>
				tiling();
			"melting" =>
				melting();
			* =>
				sys->print("unknown user function %s\n", text);
			}
	
			CUROLD = CURNEW;
			CURNEW = 1-CUROLD;
		* =>
			transform();
			if(noerr)
				run();
		}
	return 1;
}

getname()
{
	t: int = lex();

	if(t != NAME && t != FNAME && !(isalpha(t)))
		error("expected name, bad token: %d\n", t);
}

emit(what: int)
{
	if(prs >= MANY)
		error("expression too long\n", 0);
	parsed[prs++] = what;
}

error(s: string, d: int)
{
	lat: int;

	sys->fprint(fildes(2), "%s%d\n", s, d);
	while(lat != '\n')
		lat = lex();
	noerr = 0;	#  noerr is now false 
}

Pow(a: int, b: int): int
{
	c: real = real a;
	d: real = real b;

	# 	double pow(); 
	return int math->pow(c, d);
}

CART, POLAR: con iota;
Node: adt 
{
	n: int;
	typ: int;
	b: array of int;
};

run()
{
	R := array[MANY] of Node;	#  the stack    
	rr, tr: int;	#  top of stack 
	u	#  explicit destination 
	, p: array of int;	#  default  destination 
	k	#  indexes parse string 
	, a, b, c	#  scratch     
	, x, y: int;	#  coordinates 
	an, bn: Node;

	for(y = 0; y < DEF_Y; y++){
		p = src[CURNEW].pix[y];
		for(x = 0; x < DEF_X; x++){
			for((k, rr) = (0, 0); k < prs; k++){
				if(parsed[k] == VALUE){
					R[rr++].n = parsed[++k];
					continue;
				}
				if(parsed[k] == '@'){
					p[x] = R[--rr].n;
					continue;
				}
				case(parsed[k]){
				'+' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n+a;
				'-' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n-a;
				'*' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n*a;
				'/' =>
					a = R[--rr].n;
					tr = rr-1;
					if(a == 0)
						R[tr].n = 0;
					else
						R[tr].n = R[tr].n/a;
				'%' =>
					a = R[--rr].n;
					tr = rr-1;
					if(a==0)
						R[tr].n = 0;
					else
						R[tr].n = R[tr].n%a;
				'>' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n > a;
				'<' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n < a;
				GE =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n >= a;
				LE =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n <= a;
				EQ =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n == a;
				NE =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n != a;
				AND =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n && a;
				OR =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n || a;
				'^' =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = R[tr].n|a;
				'x' =>
					R[rr].typ = CART;
					R[rr++].n = x;
				'y' =>
					R[rr].typ = CART;
					R[rr++].n = y;
				'a' =>
					R[rr].typ = POLAR;
					R[rr++].n = avals[y*DEF_X + x];
				'r' =>
					R[rr].typ = POLAR;
					R[rr++].n = rvals[y*DEF_X + x];
				UMIN =>
					tr = rr-1;
					R[tr].n = -R[tr].n;
				'!' =>
					tr = rr-1;
					R[tr].n = !R[tr].n;
				'=' =>
					a = R[--rr].n;
					u = R[--rr].b;
					u[0] = a;
				RVAL =>
					an = R[--rr];
					bn = R[--rr];
					if(an.typ == CART){
						a = clamp(an.n, DEF_Y);
						b = clamp(bn.n, DEF_X);
					}else{
						b = clamp(int (real bn.n * cos(DtoR(real an.n)) + real DEF_X / 2.0), DEF_Y);
						a = clamp(int (real -bn.n * sin(DtoR(real an.n)) + real DEF_Y / 2.0), DEF_X);
					}
					tr = rr-1;
					c = R[tr].n;
					R[tr].n = int src[c].pix[a][b];
				LVAL =>
					an = R[--rr];
					bn = R[--rr];
					if(an.typ == CART){
						a = clamp(an.n, DEF_Y);
						b = clamp(bn.n, DEF_X);
					}else{
						b = clamp(int (real bn.n * cos(DtoR(real an.n)) + real DEF_X / 2.0), DEF_Y);
						a = clamp(int (real -bn.n * sin(DtoR(real an.n)) + real DEF_Y / 2.0), DEF_X);
					}
					tr = rr-1;
					c = R[tr].n;
					R[tr].b = src[c].pix[a][b:];
				POW =>
					a = R[--rr].n;
					R[rr-1].n = Pow(R[rr-1].n, a);
				'?' =>
					a = R[--rr].n;
					k++;
					if(!a)
						k = parsed[k];
				':' =>
					k = parsed[k+1];
				SIN =>
					tr = rr-1;
					R[tr].n = int (sin(DtoR(real R[tr].n)) * real Zmax);
				COS =>
					tr = rr-1;
					R[tr].n = int (cos(DtoR(real R[tr].n)) * real Zmax);
				ATAN =>
					a = R[--rr].n;
					tr = rr-1;
					R[tr].n = int RtoD(atan2(real R[tr].n, real a));
				SQRT =>
					tr = rr-1;
					R[tr].n = int sqrt(real R[tr].n);
				LOG =>
					tr = rr-1;
					if(R[tr].n > 0)
						R[tr].n = int log(real R[tr].n);
				ABS =>
					tr = rr-1;
					if(R[tr].n < 0)
						R[tr].n = - R[tr].n;
				* =>
					error("run: unknown operator\n", 0);
				}
			}
		}
	}
	CUROLD = CURNEW;
	CURNEW = 1-CUROLD;
}

lex(): int
{
	c: int;

	#  ignore white space 
	do{
		c = io.getc();
	}while(c == ' ' || c == '\t');
	if(isdigit(c))
		c = getnumber(c);
	else if(isalpha(c) || c == '_')
		c = getstring(c);
	case(c){
	Bufio->EOF =>
		c = 'q';
	'*' =>
		c = follow('*', POW, c);
	'>' =>
		c = follow('=', GE, c);
	'<' =>
		c = follow('=', LE, c);
	'!' =>
		c = follow('=', NE, c);
	'=' =>
		c = follow('=', EQ, c);
	'|' =>
		c = follow('|', OR, c);
	'&' =>
		c = follow('&', AND, c);
	'Z' =>
		c = VALUE;
		lexval = 255;
	'Y' =>
		c = VALUE;
		lexval = DEF_Y-1;
	'X' =>
		c = VALUE;
		lexval = DEF_X-1;
	'R' =>
		c = VALUE;
		lexval = int hypot(real(DEF_X/2), real(DEF_Y/2));
	'A' =>
		c = VALUE;
		lexval = 360;
	* =>
		;
	}
	return c;
}

getnumber(first: int): int
{
	c: int;

	lexval = first-'0';
	while(isdigit(c = io.getc()))
		lexval = 10*lexval+c-'0';
	pushback(c);
	return VALUE;
}

getstring(first: int): int
{
	c: int = first;
	buf:= array[128] of byte;
	n:= 0;

	do{
		buf[n++] = byte c;
		c = io.getc();
	}while(isalpha(c) || c == '_' || isdigit(c));
	pushback(c);
	text = string buf[0:n];
	case (text) {
	"new" => return NEW;
	"old" => return OLD;
	"sin" => return SIN;
	"cos" => return COS;
	"atan" => return ATAN;
	"sqrt" => return SQRT;
	"log" => return LOG;
	"abs" => return ABS;
	};
	for(c = 2; c < nsrc; c++)
		if(src[c].str == text){
			lexval = c-1;
			return FNAME;
		}
	if(len text > 1)
		return NAME;
	return first;
}

follow(tok: int, ifyes: int, ifno: int): int
{
	c: int;

	if((c = io.getc()) == tok)
		return ifyes;
	pushback(c);
	return ifno;
}

pushback(nil: int)
{
	io.ungetc();
}

getpix(into: ref SRC, str: string)
{
	#  work buffer 
	#  file name   
	fd: ref Sys->FD;
	i: int;

	if((fd = sys->open(str, Sys->OREAD)) == nil){
		fprint(fildes(2), "no file %s\n", str);
		return;
	}
	if(into.pix == nil){
		into.pix = array[DEF_Y] of array of int;
		for(i = 0; i < DEF_Y; i++)
			into.pix[i] = array[DEF_X] of int;
	}
	buf:= array[DEF_X] of byte;
	for(i = 0; i < DEF_Y; i++){
		sys->read(fd, buf, DEF_X);
		for(j:= 0; j< DEF_X; j++)
			into.pix[i][j] = int buf[j];
	}
	into.str = str;
	nsrc++;
}

putpix(into: ref SRC, str: string)
{
	fd: ref Sys->FD;
	i, j: int;
	c: int;
	buf := array[DEF_X] of byte;

	if((fd = sys->create(str, Sys->OWRITE, 8r666)) == nil){
		fprint(fildes(2), "cannot create %s\n", str);
		return;
	}
	for(i = 0; i < DEF_Y; i++){
		for(j = 0; j < DEF_X; j++){
			c = int into.pix[i][j];
			if(c ==  10 || c ==  26)
				buf[j] = byte (c-1);
			else
				buf[j] =  byte c;
		}
		sys->write(fd, buf, DEF_X);
	}
}

showfiles()
{
	n: int;

	if(nsrc == 2)
		sys->print("no files open\n");
	else
		for(n = 2; n < nsrc; n++)
			sys->print("$%d = %s\n", n-1, src[n].str);
}

lat: int;	#  look ahead token 
op := array[4] of {
	array[7] of  {
		'*',
		'/',
		'%',
		0,
		0,
		0,
		0,
	},
	array[7] of  {
		'+',
		'-',
		0,
		0,
		0,
		0,
		0,
	},
	array[7] of  {
		'>',
		'<',
		GE,
		LE,
		EQ,
		NE,
		0,
	},
	array[7] of  {
		'^',
		AND,
		OR,
		0,
		0,
		0,
		0,
	},
};

expr()
{
	remem1, remem2: int;

	level(3);
	if(lat == '?'){
		lat = lex();
		emit('?');
		remem1 = prs;
		emit(0);
		expr();
		expect(':');
		emit(':');
		remem2 = prs;
		emit(0);
		parsed[remem1] = prs-1;
		expr();
		parsed[remem2] = prs-1;
	}
}

level(nr: int)
{
	i: int;

	if(nr < 0){
		factor();
		return;
	}
	level(nr-1);
	for(i = 0; op[nr][i] != 0 && noerr; i++)
		if(lat == op[nr][i]){
			lat = lex();
			level(nr);
			emit(op[nr][i]);
			break;
		}
}

transform()
{
	prs = 0;	#  initial length of parse string 
	if(lat != NEW){
		expr();
		emit('@');
		pushback(lat);
		return;
	}
	lat = lex();
	if(lat == '['){
		fileref(CURNEW, LVAL);
		expect('=');
		expr();
		emit('=');
	}else{
		expect('=');
		expr();
		emit('@');
	}
	if(lat != '\n' && lat != ';')
		error("syntax error, separator\n", 0);
	pushback(lat);
}

factor()
{
	n: int;

	case(lat){
	'(' =>
		lat = lex();
		expr();
		expect(')');
	'-' =>
		lat = lex();
		factor();
		emit(UMIN);
	'!' =>
		lat = lex();
		factor();
		emit('!');
	OLD =>
		lat = lex();
		fileref(CUROLD, RVAL);
	FNAME =>
		n = lexval;
		lat = lex();
		fileref(n+1, RVAL);
	'$' =>
		lat = lex();
		expect(VALUE);
		fileref(lexval+1, RVAL);
	VALUE =>
		emit(VALUE);
		emit(lexval);
		lat = lex();
	'y' or 'x'  or 'a' or 'r'=>
		emit(lat);
		lat = lex();
	SIN =>
		lat = lex();
		expr();
		emit(SIN);
	COS =>
		lat = lex();
		expr();
		emit(COS);
	ATAN =>
		lat = lex();
		expect('(');
		expr();
		expect(',');
		expr();
		expect(')');
		emit(ATAN);
	ABS =>
		lat = lex();
		expr();
		emit(ABS);
	LOG =>
		lat = lex();
		expr();
		emit(LOG);
	SQRT =>
		lat = lex();
		expr();
		emit(SQRT);
	* =>
		error("expr:  error\n", lat);
	}
	if(lat == POW){
		lat = lex();
		factor();
		emit(POW);
	}
}

fileref(val: int, tok: int)
{
	if(val < 0 || val >= nsrc)
		error("bad file number: %d\n", val);
	emit(VALUE);
	emit(val);
	if(lat == '['){
		lat = lex();
		expr();
		expect(',');
		expr();	#  [x,y] 
		expect(']');
	}
	else{
		emit('x');
		emit('y');
	}
	emit(tok);
}

expect(t: int)
{
	if(lat == t)
		lat = lex();
	else
		error("error: expected token %d\n", t);
}

# 
#  *	Some user defined functions, as described in Chapter 6.
#  *	Transformations `oil()' and `melting()' are the most
#  *	time consuming. Runtime is about 10 minutes on a VAX-750.
#  *	The other transformations take less than a minute each.
#  *	A call to function `slicer()' is included as an example in main.c.
#  
N: con 3;

oil()
{
	x, y, dx, dy, mfp: int;
	histo := array[256] of int;

	for(y = N; y < DEF_Y-N; y++)
		for(x = N; x < DEF_X-N; x++){
			for(dx = 0; dx < 256; dx++)
				histo[dx] = 0;
			for(dy = y-N; dy <= y+N; dy++)
				for(dx = x-N; dx <= x+N; dx++)
					histo[int src[CUROLD].pix[dy][dx]]++;
			for(dx = dy = 0; dx < 256; dx++)
				if(histo[dx] > dy){
					dy = histo[dx];
					mfp = dx;
				}
			src[CURNEW].pix[y][x] = mfp;
		}
}

shear()
{
	x, y, r, dx, dy: int;
	yshift := array[DEF_X] of int;

	for(x = r = 0; x < DEF_X; x++){
		if(rand->rand(256) < 128)
			r--;
		else
			r++;
		yshift[x] = r;
	}
	for(y = 0; y < DEF_Y; y++){
		if(rand->rand(256) < 128)
			r--;
		else
			r++;
		for(x = 0; x < DEF_X; x++){
			dx = x+r;
			dy = y+yshift[x];
			if(dx >= DEF_X || dy >= DEF_Y || dx < 0 || dy < 0)
				continue;
			src[CURNEW].pix[y][x] = src[CUROLD].pix[dy][dx];
		}
	}
}

slicer()
{
	x, y, r, dx, dy: int;
	xshift := array[DEF_Y] of int;
	yshift := array[DEF_X] of int;

	for(x = dx = 0; x < DEF_X; x++){
		if(dx == 0){
			r = (rand->rand(64))-32;
			dx = 8+rand->rand(32);
		}
		else
			dx--;
		yshift[x] = r;
	}
	for(y = dy = 0; y < DEF_Y; y++){
		if(dy == 0){
			r = (rand->rand(64))-32;
			dy = 8+rand->rand(32);
		}
		else
			dy--;
		xshift[y] = r;
	}
	for(y = 0; y < DEF_Y; y++)
		for(x = 0; x < DEF_X; x++){
			dx = x+xshift[y];
			dy = y+yshift[x];
			if(dx < DEF_X && dy < DEF_Y && dx >= 0 && dy >= 0)
				src[CURNEW].pix[y][x] = src[CUROLD].pix[dy][dx];
		}
}

T: con 25;

tiling()
{
	x, y, dx, dy, ox, oy, nx, ny: int;

	for(y = 0; y < DEF_Y-T; y += T)
		for(x = 0; x < DEF_X-T; x += T){
			ox = (rand->rand(32))-16;	#  displacement 
			oy = (rand->rand(32))-16;
			for(dy = y; dy < y+T; dy++)
				for(dx = x; dx < x+T; dx++){
					nx = dx+ox;
					ny = dy+oy;
					if(nx >= DEF_X || ny >= DEF_Y || nx < 0 || ny < 0)
						continue;
					src[CURNEW].pix[ny][nx] = src[CUROLD].pix[dy][dx];
				}
		}
}

melting()
{
	x, y, val, k: int;

	for(k = 0; k < DEF_X*DEF_Y; k++){
		x = rand->rand(DEF_X);
		y = rand->rand(DEF_Y-1);
		while(y < DEF_Y-1 && src[CUROLD].pix[y][x] <= src[CUROLD].pix[y+1][x]){
			val = int src[CUROLD].pix[y][x];
			src[CUROLD].pix[y][x] = src[CUROLD].pix[y+1][x];
			src[CUROLD].pix[y+1][x] = val;
			y++;
		}
	}
	for(y = 0; y < DEF_Y; y++)
		for(x = 0; x < DEF_X; x++)
			src[CURNEW].pix[y][x] = src[CUROLD].pix[y][x];	#  update the other edit buffer 
}

G: con 7.5;

# extern double pow();	 the C-library routine 
matte()
{
	x, y: int;
	lookup := array[256] of int;

	for(x = 0; x < 256; x++)
		if(255.*math->pow(real x/255., G) < 3.)
			lookup[x] = 255;
		else
			lookup[x] = 0;
	for(y = 0; y < DEF_Y; y++)
		for(x = 0; x < DEF_X; x++)
			src[CURNEW].pix[y][x] = lookup[int src[CUROLD].pix[y][x]];
}



RtoD(v: real): real
{
	return v / (2.0 * Math->Pi) * 360.0;
}

DtoR(v: real): real
{
	return (v / 360.0) * 2.0 * Math->Pi;
}

rvals: array of int;
avals: array of int;

mkpolar()
{
	avals = array[DEF_X*DEF_Y] of int;
	rvals = array[DEF_X*DEF_Y] of int;
	x,y,ap,rp,ymax,ymin,xmin,xmax: int;

	ymax = DEF_Y / 2;
	ymin = -(DEF_Y - 1)/2;
	xmin = -DEF_X / 2;
	xmax = (DEF_X - 1)/2;
	ap=0;
	rp=0;
	for(y = ymax; y >= ymin; y--){
		for(x= xmin; x <= xmax; x++){
			xd := real x;
			yd := real y;
			avals[ap++] = int RtoD(atan2(yd, xd));
			rvals[rp++] = int hypot(xd, yd);
		}
	}
}


dowrap:=0;
clamp(n: int, max: int): int
{
	if(dowrap)
		return wrap(n, max);
	else
		return minmax(n, max);
}

wrap(n: int, max: int): int
{
	while(n < 0)
		n+= max;
	if(n>=max)
		return n%max;
	else 
		return n;
}

minmax(n: int, max: int): int
{
	if(n < 0)
		return 0;
	else if(n >= max)
		return max -1;
	else
		return n;
}


getimg(): ref Draw->Image
{
	i, j: int;
	c: int;
	buf := array[DEF_X*DEF_Y] of byte;
	into := src[CUROLD];
	for(i = 0; i < DEF_Y; i++){
		for(j = 0; j < DEF_X; j++){
			c = int into.pix[i][j];
			if(c ==  10 || c ==  26)
				buf[(i*DEF_X) + j] = byte (c-1);
			else
				buf[(i*DEF_X) + j] =  byte c;
		}
	}
	image := ctxt.display.newimage(Rect((0,0),(DEF_X,DEF_Y)), Draw->GREY8, 0, Draw->Black);
	image.writepixels(Rect((0,0),(DEF_X,DEF_Y)), buf);
	return image;
}

cmd(t: ref Tk->Toplevel, arg: string): string
{
	rv := tk->cmd(t,arg);
	if(rv!=nil && rv[0]=='!')
		print("tk->cmd(%s): %s\n",arg,rv);
	return rv;
}

reader(img: chan of ref Image)
{
	do{
		noerr=1;
		image := getimg();
		img <-= image;
	}while(parse());
	image := getimg();
	img <-= image;
}

viewer(img: chan of ref Image)
{
	(top, ctl) := tkclient->toplevel(ctxt, nil, "Popi", Tkclient->Appl);

	cmd(top, sys->sprint("panel .c -width %d -height %d", DEF_X, DEF_Y));
	cmd(top, "pack .c; update");

	tkclient->startinput(top, "ptr" :: "kbd" :: nil);
	tkclient->onscreen(top, nil);
	for(;;) alt {
	s := <-ctl or
	s =  <-top.ctxt.ctl or
	s = <-top.wreq =>
		tkclient->wmctl(top, s);
	p := <-top.ctxt.ptr =>
		tk->pointer(top, *p);
	c := <-top.ctxt.kbd =>
		tk->keyboard(top, c);
	i := <- img =>
		if(i == nil)
			exit;
		tk->putimage(top, ".c", i, nil);
		cmd(top, "update");
	}

}
