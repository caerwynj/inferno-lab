implement Board;

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Display, Screen, Image, Point, Rect: import draw;
include "math.m";
	math: Math;
include "ir.m";
include "mux.m";
	mux: Mux;
include "daytime.m";
	daytime: Daytime;
include "rand.m";
	rand: Rand;

Board: module
{
	init:	fn(nil: ref Mux->Context, nil: list of string);
};

display: ref Display;
screen: ref Screen;
dots: ref Image;
anim: ref Image;
animmask: ref Image;
background: ref Image;
offset := Point(18,10);

ZP := Point(0, 0);
first:=1;

nosleep, printout, auto: int;

init(ctxt: ref Mux->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	mux = load Mux Mux->PATH;
	daytime = load Daytime Daytime->PATH;
	rand = load Rand Rand->PATH;
	rand->init(daytime->now());
	daytime = nil;
	
	sys->pctl(Sys->NEWPGRP, nil);
	printout = 1;
	
	display = ctxt.display;
	screen = ctxt.screen;
	screen.image.flush(Draw->Flushoff);
	ctxt.ctomux <-= Mux->AMstartptr;
	ctxt.ctomux <-= Mux->AMstartir;

	background = drawbackground();
	dots = drawdots();
	background.draw(background.r, dots, nil, ZP);
	anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
	animmask = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);

	drawboard(screen.image.r);
	pid := -1;
	sync := chan of int;
	mvch := chan of (int, int, int);
	initboard();
	spawn game(sync, mvch, 0);
	pid = <- sync;
	for(;;) alt{
	p := <-ctxt.cptr =>
		if(p.buttons & 1){
			(x,y) := findrect(p.xy);
			sys->print("ptr %d %d: %d %d\n", p.xy.x, p.xy.y, x, y);
		 	op := Point(x*28, y*21);
			if(p.xy.in(Rect(op,op.add(Point(20,20))).addpt(offset))){
				alt {
				mvch <-= (SQUARE, x+1, y+1) =>
				;
				* =>
				;
				}
			}
		}
	ir := <-ctxt.cir =>
		case ir {
		Ir->Power or Ir->Enter =>
			ctxt.ctomux <-= Mux->AMexit;
			return;
		}
	}
}

turn := 0;
animate(p: Point, turn: int)
{
	r := Rect(p, p.add(Point(20,20)));
	(checker, mask) := drawchecker(turn);
	anim = display.newimage(display.image.r, Draw->RGBA32, 0, Draw->Transparent);
	for (i := 0; i < 16; i++){
		anim.draw(r, checker, mask, ZP);
		drawboard(r);
		sys->sleep(50);
	}
#	for(i = 0; i < 4; i++){
#		anim.fillellipse(p.add(Point(10,10)), i, i, display.white, ZP);
#		drawboard(r);
#		sys->sleep(50);
#	}
}

mkstone() : (ref Image, ref Image)
{
	center := Point(10,10);
	h := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	mask := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	h.fillellipse(center, 7, 7, display.white, ZP);
	mask.ellipse(center, 7,7, 1, display.color(5), ZP);
	mask.ellipse(center, 6,6, 1, display.color(10), ZP);
	mask.ellipse(center, 5, 5, 1, display.color(20), ZP);
	mask.ellipse(center, 4, 4, 1, display.color(30), ZP);
	mask.ellipse(center, 3, 3, 1, display.color(40), ZP);
	mask.ellipse(center, 2, 2, 1, display.color(50), ZP);
	mask.ellipse(center, 1, 1, 1, display.color(60), ZP);
	mask.fillellipse(center, 0, 0, display.color(250), ZP);

	return (h, mask);
}

drawdots(): ref Image
{
	layer := display.newimage(Rect((0,0),(256,192)), Draw->RGBA32, 0, Draw->Transparent);
	(dot, mask) := mkstone();
	center := Point(10,10);
	for(i := 0; i < 8; i++){   # horizontal
		for(j :=0; j < 8; j++){	# vertical
		 	p := Point(i*28, j*21);
			layer.draw(Rect(p,p.add(Point(20,20))).addpt(offset), dot, mask, ZP);
		}
	}
	return layer;
}

findrect(p: Point): (int, int)
{
	x := (p.x - 18) / 28;
	y := (p.y - 10) / 21;
	return (x,y);
}


drawbackground(): ref Image
{
	bg := display.newimage(display.image.r, Draw->RGBA32, 0, Draw->White);
	r := bg.r;
	y := r.dy();
	d := y/48;
	
	for(i:=0; i < 48; i++){
		bg.ellipse(Point(r.dx()/2, r.dy()/2), i*4, i*4, 2, display.rgb(0,0,255-(i*5)), ZP);
	}
	return bg;
}

drawchecker(p: int): (ref Image, ref Image)
{
	if(p == BLACK)
		src := display.colormix(Draw->White,Draw->Red);
	else
		src = display.white;
		
	center := Point(10,10);
	h := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	mask := display.newimage(Rect((0,0),(20,20)), Draw->RGBA32, 0, Draw->Transparent);
	h.fillellipse(center, 9, 9, src, ZP);
	mask.ellipse(center, 9,9, 1, display.color(1), ZP);
	mask.ellipse(center, 8,8, 1, display.color(2), ZP);
	mask.ellipse(center, 7,7, 1, display.color(3), ZP);
	mask.ellipse(center, 6,6, 1, display.color(4), ZP);
	mask.ellipse(center, 5, 5, 1, display.color(5), ZP);
	mask.ellipse(center, 4, 4, 1, display.color(6), ZP);
	mask.ellipse(center, 3, 3, 1, display.color(7), ZP);
	mask.ellipse(center, 2, 2, 1, display.color(8), ZP);
	mask.ellipse(center, 1, 1, 1, display.color(9), ZP);
	mask.fillellipse(center, 2, 2, display.color(10), ZP);

	return (h, mask);
}

#combine all the layers
drawboard(r: Rect)
{
	screen.image.draw(r, background, nil, r.min);
#	screen.image.draw(r, dots, nil, r.min);
	screen.image.draw(r, anim, nil, r.min);
	screen.image.flush(Draw->Flushnow);
}

SQUARE, REPLAY: con iota;

WIDTH: con 400;
HEIGHT: con 400;

SZB: con 8;		# must be even
SZF: con SZB+2;
MC1: con SZB/2;
MC2: con MC1+1;
PIECES: con SZB*SZB;
SQUARES: con PIECES-4;
MAXMOVES: con 3*PIECES/2;
NOMOVE: con SZF*SZF - 1;

BLACK, WHITE, EMPTY, BORDER: con iota;
MACHINE, HUMAN: con iota;
SKILLB : con 6;
SKILLW : con 0;
MAXPLIES: con 6;

moves: array of int;
board: array of array of int;	# for display
brd: array of array of int;		# for calculations
val: array of array of int;
order: array of (int, int);
pieces: array of int;
value: array of int;
kind: array of int;
skill: array of int;
name: array of string;

brdimg: ref Image;
brdr: Rect;
brdx, brdy: int;

black, white, green: ref Image;

movech: chan  of (int, int, int);

game(sync: chan of int, mvch: chan of (int, int, int), again: int)
{
	sync <-= sys->pctl(0, nil);
	movech = mvch;
	initbrd();
	for(i := 1; i <= SZB; i++){
		for(j := 1; j <= SZB; j++){
			if (board[i][j] == BLACK || board[i][j] == WHITE)
				drawpiece(i, j, board[i][j], 0);
		}
	}
	if(again)
		replay(moves);
	else
		play();
	sync <-= 0;
}

ordrect()
{
	i, j : int;

	n := 0;
	for(i = 1; i <= SZB; i++){
		for(j = 1; j <= SZB; j++){
			if(i < SZB/2 || j < SZB/2 || i > SZB/2+1 || j > SZB/2+1)
				order[n++] = (i, j);
		}
	}
	for(k := 0; k < SQUARES-1; k++){
		for(l := k+1; l < SQUARES; l++){
			(i, j) = order[k];
			(a, b) := order[l];
			if(val[i][j] > val[a][b])
				(order[k], order[l]) = (order[l], order[k]);
		}
	}
}

initboard()
{
	i, j, k: int;

	moves = array[MAXMOVES+1] of int;
	board = array[SZF] of array of int;
	brd = array[SZF] of array of int;
	for(i = 0; i < SZF; i++){
		board[i] = array[SZF] of int;
		brd[i] = array[SZF] of int;
	}
	val = array[SZF] of array of int;
	s := -pow(-1, SZB/2);
	for(i = 0; i < SZF; i++){
		val[i] = array[SZF] of int;
		val[i][0] = val[i][SZF-1] = 0;
		for(j = 1; j <= SZB; j++){
			for(k = SZB/2; k > 0; k--){
				if(i == k || i == SZB+1-k || j == k || j == SZB+1-k){
					val[i][j] = s*pow(-7, SZB/2-k);
					break;
				}
			}
		}
	}
	order = array[SQUARES] of (int, int);
	ordrect();
	pieces = array[2] of int;
	value = array[2] of int;
	kind = array[2] of int;
	kind[BLACK] = MACHINE;
	if(auto)
		kind[WHITE] = MACHINE;
	else
		kind[WHITE] = HUMAN;
	skill = array[2] of int;
	skill[BLACK] = SKILLB;
	skill[WHITE] = SKILLW;
	name = array[2] of string;
	name[BLACK] = "black";
	name[WHITE] = "white";
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
	green = display.color(Draw->Green);
}

initbrd()
{
	i, j: int;

	for(i = 0; i < SZF; i++)
		for(j = 0; j < SZF; j++)
			brd[i][j] = EMPTY;
	for(i = 0; i < SZF; i++)
		brd[i][0] = brd[i][SZF-1] = BORDER;
	for(j = 0; j< SZF; j++)
		brd[0][j] = brd[SZF-1][j] = BORDER;
	brd[MC1][MC1] = brd[MC2][MC2] = BLACK;
	brd[MC1][MC2] = brd[MC2][MC1] = WHITE;
	for(i = 0; i < SZF; i++)
		for(j = 0; j < SZF; j++)
			board[i][j] = brd[i][j];
	pieces[BLACK] = pieces[WHITE] = 2;
	value[BLACK] = value[WHITE] = -2;
}

plays := 0;
bscore := 0;
wscore := 0;
bwins := 0;
wwins := 0;

play()
{
	n := 0;
	for(i := 0; i <= MAXMOVES; i++)
		moves[i] = NOMOVE;
	if(plays&1)
		(first, second) := (WHITE, BLACK);
	else
		(first, second) = (BLACK, WHITE);
	if(printout)
		sys->print("%d\n", first);
	moves[n++] = first;
	m1 := m2 := 1;
	for(;;){
		if(pieces[BLACK]+pieces[WHITE] == PIECES)
			break;
		m2 = m1;
		m1 = move(first, second);
		if(printout)
			sys->print("%d\n", m1);
		moves[n++] = m1;
		if(!m1 && !m2)
			break;
		(first, second) = (second, first);
	}
	if(auto)
		sys->print("score: %d-%d\n", pieces[BLACK], pieces[WHITE]);
	bscore += pieces[BLACK];
	wscore += pieces[WHITE];
	if(pieces[BLACK] > pieces[WHITE])
		bwins++;
	else if(pieces[BLACK] < pieces[WHITE])
		wwins++;
	plays++;
	if(auto)
		sys->print("	black: %d white: %d draw: %d total: (%d-%d)\n", bwins, wwins, plays-bwins-wwins, bscore, wscore);
	puts(sys->sprint("black %d:%d white", pieces[BLACK], pieces[WHITE]));
	sleep(2000);
	puts(sys->sprint("black %d:%d white", bwins, wwins));
	sleep(2000);
}

replay(moves: array of int)
{
	n := 0;
	first := moves[n++];
	second := BLACK+WHITE-first;
	m1 := m2 := 1;
	while (pieces[BLACK]+pieces[WHITE] < PIECES){
		m2 = m1;
		m1 = moves[n++];
		if(m1 == NOMOVE)
			break;
		if(m1 != 0)
			makemove(m1/SZF, m1%SZF, first, second, 1, 0);
		if(!m1 && !m2)
			break;
		(first, second) = (second, first);
	}
	# sys->print("score: %d-%d\n", pieces[BLACK], pieces[WHITE]);
}

move(me: int, you: int): int
{
	if(kind[me] == MACHINE){
		puts("machine " + name[me] + " move");
		m := genmove(me, you);
		if(!m){
			puts("machine " + name[me] + " cannot go");
			sleep(2000);
		}
		return m;
	}
	else{
		m, n: int;

		mvs := findmoves(me, you);
		if(mvs == nil){
			puts("human " + name[me] + " cannot go");
			sleep(2000);
			return 0;
		}
		for(;;){
			puts("human " + name[me] + " move");
			(m, n) = getmove();
			if(m < 1 || n < 1 || m > SZB || n > SZB)
				continue;
			if(brd[m][n] == EMPTY)
				(valid, nil) := makemove(m, n, me, you, 0, 0);
			else
				valid = 0;
			if(valid)
				break;
			puts("illegal move");
			sleep(2000);
		}
		makemove(m, n, me, you, 1, 0);
		return m*SZF+n;
	}
}

fullsrch: int;

genmove(me: int, you: int): int
{
	m, n, v: int;

	mvs := findmoves(me, you);
	if(mvs == nil)
		return 0;
	if(skill[me] == 0){
		l := len mvs;
		r := rand->rand(l);
		# r = 0;
		while(--r >= 0)
			mvs = tl mvs;
		(m, n) = hd mvs;
	}
	else{
		plies := skill[me];
		left := PIECES-(pieces[BLACK]+pieces[WHITE]);
		if(left < plies)		# limit search
			plies = left;
		else if(left < 2*plies)	# expand search to end
			plies = left;
		else{				# expand search nearer end of game
			k := left/plies;
			if(k < 3)
				plies = ((k+2)*plies)/(k+1);
		}
		fullsrch = plies == left;
		visits = leaves = 0;
		(v, (m, n)) = minimax(me, you, plies, ∞, 1);
		if(0){
		# if((m==2&&n==2&&brd[1][1]!=BLACK) ||
		#    (m==2&&n==7&&brd[1][8]!=BLACK) ||
		#    (m==7&&n==2&&brd[8][1]!=BLACK) ||
		#    (m==7&&n==7&&brd[8][8]!=BLACK)){
			while(mvs != nil){
				(a, b) := hd mvs;
				(nil, sqs) := makemove(a, b, me, you, 1, 1);
				(v0, nil) := minimax(you, me, plies-1, ∞, 1);
				sys->print("	(%d, %d): %d\n", a, b, v0);
				undomove(a, b, me, you, sqs);
				mvs = tl mvs;
			}
			if(!fullsrch){
				sys->print("best move is %d, %d\n", m, n);
				kind[WHITE] = HUMAN;
			}
		}
		if(auto)		
			sys->print("eval = %d plies=%d goes=%d visits=%d\n", v, plies, len mvs, leaves);
	}
	makemove(m, n, me, you, 1, 0);
	return m*SZF+n;
}

findmoves(me: int, you: int): list of (int, int)
{
	mvs: list of (int, int);

	for(k := 0; k < SQUARES; k++){
		(i, j) := order[k];
		if(brd[i][j] == EMPTY){
			(valid, nil) := makemove(i, j, me, you, 0, 0);
			if(valid)
				mvs = (i, j) :: mvs;
		}
	}
	return mvs;
}

makemove(m: int, n: int, me: int, you: int, move: int, gen: int): (int, list of (int, int))
{
	sqs: list of (int, int);

	if(move){
		pieces[me]++;
		value[me] += val[m][n];
		brd[m][n] = me;
		if(!gen){
			board[m][n] = me;
			drawpiece(m, n, me, 1);
			sleep(1000);
		}
	}
	valid := 0;
	for(i := -1; i < 2; i++){
		for(j := -1; j < 2; j++){
			if(i != 0 || j != 0){
				v: int;

				(v, sqs) = dirmove(m, n, i, j, me, you, move, gen, sqs);
				valid |= v;
				if (valid && !move)
					return (1, sqs);
			}
		}
	}
	if(!valid && move)
		fatal(sys->sprint("bad makemove call (%d, %d)", m, n));
	return (valid, sqs);
}

dirmove(m: int, n: int, dx: int, dy: int, me: int, you: int, move: int, gen: int, sqs: list of (int, int)): (int, list of (int, int))
{
	p := 0;
	m += dx;
	n += dy;
	while(brd[m][n] == you){
		m += dx;
		n += dy;
		p++;
	}
	if(p > 0 && brd[m][n] == me){
		if(move){
			pieces[me] += p;
			pieces[you] -= p;
			m -= p*dx;
			n -= p*dy;
			while(--p >= 0){
				brd[m][n] = me;
				value[me] += val[m][n];
				value[you] -= val[m][n];
				if(gen)
					sqs = (m, n) :: sqs;
				else{
					board[m][n] = me;
					drawpiece(m, n, me, 0);
					# sleep(500);
				}
				m += dx;
				n += dy;
			}
		}
		return (1, sqs);
	}
	return (0, sqs);
}			

undomove(m: int, n: int, me: int, you: int, sqs: list of (int, int))
{
	brd[m][n] = EMPTY;
	pieces[me]--;
	value[me] -= val[m][n];
	for(; sqs != nil; sqs = tl sqs){
		(x, y) := hd sqs;
		brd[x][y] = you;
		pieces[me]--;
		pieces[you]++;
		value[me] -= val[x][y];
		value[you] += val[x][y];
	}
}

getmove(): (int, int)
{
	k, x, y: int;

	(k, x, y) = <- movech;
	if(k == REPLAY){
		return getmove();
	}
	return (x, y);
}

drawpiece(m, n, p, flash: int)
{
	(x,y) := (m-1, n-1);
	op := Point(x*28, y*21);
	animate(op.add(offset), p);
}

∞: con (1<<30);
MAXVISITS: con 1024;

visits, leaves : int;

minimax(me: int, you: int, plies: int, αβ: int, mv: int): (int, (int, int))
{
	if(plies == 0){
		visits++;
		leaves++;
		if(visits == MAXVISITS){
			visits = 0;
			sys->sleep(0);
		}
		return (eval(me, you), (0, 0));
	}
	mvs := findmoves(me, you);
	if(mvs == nil){
		if(mv)
			(v, nil) := minimax(you, me, plies, ∞, 0);
		else
			(v, nil) = minimax(you, me, plies-1, ∞, 0);
		return (-v, (0, 0));
	}
	bestv := -∞;
	bestm := (0, 0);
	e := 0;
	for(; mvs != nil; mvs = tl mvs){
		(m, n) := hd mvs;
		(nil, sqs) := makemove(m, n, me, you, 1, 1);
		(v, nil) := minimax(you, me, plies-1, -bestv, 1);
		v = -v;
		undomove(m, n, me, you, sqs);
		if(v > bestv || (v == bestv && rand->rand(++e) == 0)){
			if(v > bestv)
				e = 1;
			bestv = v;
			bestm = (m, n);
			if(bestv >= αβ)
				return (∞, (0, 0));
		}
	}
	return (bestv, bestm);
}
	
eval(me: int, you: int): int
{
	d := pieces[me]-pieces[you];
	if(fullsrch)
		return d;
	n := pieces[me]+pieces[you];
	v := 0;
	for(i := 1; i <= SZB; i += SZB-1)
		for(j := 1; j <= SZB; j += SZB-1)
			v += line(i, j, me, you);
	return (PIECES-n)*(value[me]-value[you]+v) + n*d;
}

line(m: int, n: int, me: int, you: int): int
{
	if(brd[m][n] == EMPTY)
		return 0;
	dx := dy := -1;
	if(m == 1)
		dx = 1;
	if(n == 1)
		dy = 1;
	return line0(m, n, 0, dy, me, you) +
		   line0(m, n, dx, 0, me, you) +
		   line0(m, n, dx, dy, me, you);
}

line0(m: int, n: int, dx: int, dy: int, me: int, you: int): int
{
	v := 0;
	p := brd[m][n];
	i := val[1][1];
	while(brd[m][n] == p){
		v += i;
		m += dx;
		n += dy;
	}
	if(p == you)
		return -v;
	if(p == me)
		return v;
	return v;
}

pow(n: int, m: int): int
{
	p := 1;
	while(--m >= 0)
		p *= n;
	return p;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	exit;
}

sleep(t: int)
{
	if(nosleep)
		sys->sleep(0);
	else
		sys->sleep(t);
}

kill(pid: int): int
{
	fd := sys->open("#p/"+string pid+"/ctl", Sys->OWRITE);
	if(fd == nil)
		return -1;
	if(sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}
	
puts(s: string)
{
	sys->print("%s\n", s);
}
