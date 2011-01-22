implement C4;

#
#	Multi player connect four game.
#	Server gamed is used for rondezvous.
#	After connection opponent runs in step lock.
#	Bruce Ellis - October 1996.
#

include "sys.m";
include "draw.m";
include "ir.m";
include "gamer.m";
include "mux.m";

sys: Sys;
FD, Connection: import sys;
draw: Draw;
Display, Point, Rect, Font, Image, Screen: import draw;
gamer: Gamer;
Game: import gamer;
mux: Mux;
Context: import mux;

stderr: ref FD;

E: con 20;	# edge pixels
F: con 6;	# frame pixels
M: con 7;	# columns
N: con 6;	# rows

TOFFX: con 10;	# text offset, x
TOFFY: con 5;	# text offset, y

A, B, C, R: int;	# calculated sizes

TC: Point;	# top left corner
BD: Rect;	# board
FR: Rect;	# frame
TX: Rect;	# text arena

screen: ref Screen;
display: ref Display;
disp: ref Image;
textfont: ref Font;
blue, yellow, red, black, white, green, back, textcol, ones: ref Image;

Empty: con 0;
PlayRed: con 1;
PlayBlack: con 2;

contents: array of array of int;
winners: array of (int, int);

iam: int;

C4: module
{
	init:	fn(ctxt: ref Mux->Context, argv: list of string);
};

init(ctxt: ref Mux->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
	stderr = sys->fildes(2);
	gamer = load Gamer Gamer->PATH;
	if (gamer == nil) {
		sys->fprint(stderr, "could not load %s: %r\n", Gamer->PATH);
		return;
	}

	contents = array[N] of array of int;

	for (i := 0; i < N; i++)
		contents[i] = array[M] of int;

	winners = array[4] of (int, int);
	screen = ctxt.screen;
	display = ctxt.display;
	textfont = Font.open(display, "*default*");
	blue = display.color(Draw->Blue);
	yellow = display.color(Draw->Yellow);
	red = display.color(Draw->Red);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
	green = display.color(Draw->Green);
	textcol = white;
	ones = display.color(Draw->White);
	scale(screen.image.r);
	backblue := display.rgb2cmap(0, 0, 255);
	back = display.color(backblue);
	disp = screen.newwindow(BD, 0, backblue);
	disp.draw(FR, yellow, ones, (0, 0));
	game(ctxt.cir);
}

# calculate sizes
scale(r: Rect)
{
	z: int;

	dx := r.dx();
	dy := r.dy();

	if (dx < dy)
		z = dx;
	else
		z = dy;

	C = (z - E) / (M + 1);
	B = 2 * C / 3;

	if ((B % 2) == 1)
		B--;

	R = B / 2;
	A = (B / 3) + 1;

	if (A > E / 2)
		A = E / 2;

	A += R;
	TC.x = (dx - (2 * A + (M - 1) * C)) / 2;
	TC.y = ((dy - (2 * A + (N - 1) * C)) / 2) + B;
	FR.min = TC;
	FR.max.x = TC.x + 2 * A + (M - 1) * C;
	FR.max.y = TC.y + 2 * A + (N - 1) * C;
	BD.min = FR.min.sub((F, F + C));
	BD.max = FR.max.add((F, F));
	TX.min = BD.min;
	TX.max.x = BD.max.x;
	TX.max.y = FR.min.y;
}

# draw the holes
holes()
{
	for (i := 0; i < M; i++)
		for (j := 0; j < N; j++) {
			puck(i, j, blue);
			contents[j][i] = Empty;
		}
}

# play the game
game(irc: chan of int)
{
	g: Game;
	am: string;
	c: ref Image;

	holes();

#	g = gamer->Join("connect4");
#	if (g.player < 0)
#		return;
#	else if (g.player == 0) {
		iam = PlayRed;
		am = "red";
		c = red;
#	}
#	else {
#		iam = PlayBlack;
#		am = "black";
#		c = black;
#	}

	drawbase(c);
	disptext("You are " + am + ", playing " + "...");
#	sys->sleep(5000);
	cleartext();

	player := PlayRed;
	count := 0;

	while (count < M * N && makemove(player, g, irc) == 0) {
		if (player == PlayRed)
			player = PlayBlack;
		else
			player = PlayRed;

		count++;
	}

#	g.Exit();
}

# check input before passing to opponent
goodmove(kn: int) : int
{
	case kn {
	Ir->FF or
	Ir->Rew or
	Ir->Power or
	Ir->Select =>
		return 1;
	* =>
		return 0;
	}
}

# one round, either you or opponent
makemove(player: int, g: Game, irc: chan of int) : int
{
	color: ref Image;
	kn: int;

	pos := (M - 1) / 2;

	if (player == PlayRed)
		color = red;
	else
		color = black;

	puck(pos, -1, color);

	for (;;) {
#		if (player == iam) {
			do
				kn = <- irc;
			while (!goodmove(kn));
#			g.Out(kn);
#		} else
#			kn = g.In();
		case kn {
		Ir->FF =>
			puck(pos, -1, blue);
			pos++;
			if (pos == M)
				pos = 0;
			puck(pos, -1, color);
		Ir->Rew =>
			puck(pos, -1, blue);
			pos--;
			if (pos < 0)
				pos = M - 1;
			puck(pos, -1, color);
		Ir->Power or Ir->Enter =>
			outcome(player != iam, "Forfeit");
			<- irc;
			return 1;
		Ir->Select =>
			if (contents[0][pos] == Empty) {
				row := -1;
				do {
					puck(pos, row, blue);
					row++;
					puck(pos, row, color);
					sys->sleep(2);
				} while (row < N - 1 && contents[row + 1][pos] == Empty);
				contents[row][pos] = player;
				if (winner(player)) {
					halo(color);
					outcome(player == iam, "Four in a row");
					<- irc;
					return 1;
				}
				return 0;
			}
		}
	}
}

# check if the player that just moved has won
winner(player: int) : int
{
	i, j: int;

	for (i = 0; i < M - 3; i++)
		for (j = 0; j < N; j++) {
			if (horizontal(i, j, player) != 0)
				return 1;
		}

	for (i = 0; i < M; i++)
		for (j = 0; j < N - 3; j++) {
			if (vertical(i, j, player) != 0)
				return 1;
		}

	for (i = 0; i < M - 3; i++)
		for (j = 0; j < N - 3; j++) {
			if (diagonal(i, j, 1, player) != 0)
				return 1;
		}

	for (i = 3; i < M; i++)
		for (j = 0; j < N - 3; j++) {
			if (diagonal(i, j, -1, player) != 0)
				return 1;
		}

	return 0;
}

# different ways to win

horizontal(x, y, player: int) : int
{
	for (i := 0; i < 4; i++) {
		if (contents[y][x + i] != player)
			return 0;

		winners[i] = (x + i, y);
	}

	return 1;
}

vertical(x, y, player: int) : int
{
	for (i := 0; i < 4; i++) {
		if (contents[y + i][x] != player)
			return 0;

		winners[i] = (x, y + i);
	}

	return 1;
}

diagonal(x, y, delta, player: int) : int
{
	for (i := 0; i < 4; i++) {
		if (contents[y + i][x] != player)
			return 0;

		winners[i] = (x, y + i);
		x += delta;
	}

	return 1;
}

# draw a green halo around the winning four
halo(c: ref Image)
{
	for (i := 0; i < 4; i++) {
		(x, y) := winners[i];
		circle(x, y, R, green);
		circle(x, y, R - 2, c);
	}
}

# draw a rectangle at the base to show player's colour
drawbase(c: ref Image)
{
	b: Rect;

	b = BD;
	b.min.y = FR.max.y;
	disp.draw(b, c, ones, (0, 0));
}

# clear the text rectangle
cleartext()
{
	disp.draw(TX, back, ones, (0, 0));
}

# display a string in the text rectangle
disptext(s: string)
{
	disp.text(TX.min.add((TOFFX, TOFFY)), textcol, (0, 0), textfont, s);
}

# display outcome string
outcome(won: int, reason: string)
{
	did: string;

	if (won)
		did = "won";
	else
		did = "lost";

	disptext("You " + did + " - " + reason);
}

# circle routine, for pucks and halo
circle(x, y, r: int, c: ref Image)
{
	disp.fillellipse(TC.add((A + x * C, A + y * C)), r, r, c, (0, 0));
}

# draw a played piece
puck(x, y: int, c: ref Image)
{
	circle(x, y, R, c);
}
