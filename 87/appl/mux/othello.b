implement othello;

#
#	Multi player othello game.
#	the server othellodemon is used for rendezvous.
#	After connection opponent runs in step lock.
#	Based on parts from Bruce Ellis's connect four game - October 1996.
#

include "sys.m";
include "draw.m";
include "ir.m";
include "gamer.m";
include "mux.m";
	mux: Mux;
	Context: import mux;

sys: Sys;
gamer: Gamer;
Game: import gamer;

FD, Connection: import sys;
draw: Draw;
Display, Point, Rect, Font, Image, Screen: import draw;

stderr: ref FD;

E: con 20;	# edge pixels
F: con 6;	# frame pixels
M: con 8;	# columns and columns

TOFFX: con 10;	# text offset, x
TOFFY: con 5;	# text offset, y

A, B, C, R: int;	# calculated sizes

TC: Point;	# top left corner
BD: Rect;	# board
FR: Rect;	# frame
TX: Rect;	# text arena
TX0: Rect;	# text arena

sysname: con "/dev/sysname";

screen: ref Screen;
display: ref Display;
disp: ref Image;
textfont: ref Font;
hole, texture, blue, yellow,  red, black, white, green, back, textcol, ones: ref Image;

Empty: con 0;
PlayWhite: con 1;
PlayBlack: con 2;

contents: array of array of int;

iam: int;
move: int;
opi, opo, opr, opx: chan of int;

othello: module
{
	init:	fn(ctxt: ref Context,nil: list of string);
};

grain := array[] of {
        (0, 0), (1, 1), (2, 1), (3, 1),
        (3, 2), (3, 3), (4, 3), (4, 4),
        (5, 5)
};
 
shadow := array[] of {
        (0, 1), (1, 2), (2, 2), (3, 4),
        (4, 5), (5, 0)
};
 
maketexture()
{
        i: int;
 
        texture = display.newimage(Rect((0, 0), (6, 6)), display.image.chans, 1, 16r80FF);
        gval := array[] of { byte 255, byte 255, byte 255, byte 255 };
        sval := array[] of { byte 0, byte 0, byte 0, byte 0 };
 
        for (i = 0; i < len grain; i++) {
                (x, y) := grain[i];
                texture.writepixels(((x, y), (x + 1, y + 1)), gval);
        }
 
        for (i = 0; i < len shadow; i++) {
                (x, y) := shadow[i];
                texture.writepixels(((x, y), (x + 1, y + 1)), sval);
        }
}

init(ctxt: ref Context,nil: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	mux = load Mux Mux->PATH;
	stderr = sys->fildes(2);
	move = 0;

	contents = array[M] of array of int;

	for (i := 0; i < M; i++)
		contents[i] = array[M] of int;

	screen = ctxt.screen;
	display = ctxt.display;
	textfont = Font.open(display, "*default*");
	blue = display.color(Draw->Blue);
	hole = display.color(16rC3FF);
	yellow = display.color(Draw->Yellow);
	red = display.color(Draw->Red);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);
	green = display.color(Draw->Green);
	textcol = white;
	ones = display.color(Draw->White);
	scale(screen.image.r);
	backblue := display.rgb2cmap(0, 0, 144);
	back = display.rgb(0, 0, 144);
	disp = screen.newwindow(BD, 0, backblue);
	maketexture();
	disp.draw(FR, texture, nil, (0, 0));

	sys = load Sys Sys->PATH;
        stderr = sys->fildes(2);
        gamer = load Gamer Gamer->PATH;
        if (gamer == nil) {
                sys->fprint(stderr, "could not load %s: %r\n", Gamer->PATH);
                return;
        }

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
	TC.y = ((dy - (2 * A + (M - 1) * C)) / 2) + B;
	FR.min = TC;
	FR.max.x = TC.x + 2 * A + (M - 1) * C;
	FR.max.y = TC.y + 2 * A + (M - 1) * C;
	BD.min = FR.min.sub((F, F + C));
	BD.max = FR.max.add((F, F));
	TX0.min.x = BD.min.x;
	TX0.min.y = FR.min.y - 25;
	TX0.max.x = BD.max.x;
	TX0.max.y = FR.min.y;
	TX.min = BD.min;
	TX.max.x = BD.max.x;
	TX.max.y = FR.min.y - 25;
}

# draw the holes, place initial stones
holes()
{
	for (i := 0; i < M; i++)
		for (j := 0; j < M; j++) {
			puck(i, j, hole);
			contents[j][i] = Empty;
		}

	puck(M/2-1,M/2-1,white);
	contents[M/2-1][M/2-1] = PlayWhite;
	puck(M/2-1,M/2,black);
	contents[M/2-1][M/2] = PlayBlack;
	puck(M/2,M/2,white);
	contents[M/2][M/2] = PlayWhite;
	puck(M/2,M/2-1,black);
	contents[M/2][M/2-1] = PlayBlack;
}

# play the game
game(irc: chan of int)
{
	g: Game;
	who: string;
	holes();

	g = gamer->Join("othello");
	sys->fprint(stderr, "joined\n");
	count := 4;
#	if (g.player < 0)
#               return;

#	if(g.player == 0) {
		iam = PlayWhite;
                who = "white";
#	}
#	else {
#		iam = PlayBlack;
#              	who = "black";
#	}

	disptext0( "you play " + who + " playing, "  + g.opponent);
	sys->sleep(3000);
	player := PlayWhite;

	while (count < M * M )
	{
		#sys->fprint(stderr, "count %d\n",count);
		if(canmove(player))
		{
			if(makemove(player, g, irc) != 0)
				break;
			count++;
		}
		else
		{
 
        		if (player == PlayWhite) 
                		who = "white";
        		else
                		who= "black";

			disptext(who + " can't move");
			sys->sleep(3000);
			cleartext();
			
		}

		if (player == PlayWhite)
			player = PlayBlack;
		else
			player = PlayWhite;

	}
	if(count == M * M)
		winner();
	g.Exit();
	<- irc;
}

# check input before passing to opponent
goodmove(kn: int) : int
{
	case kn {
	Ir->FF or
	Ir->Rew or
	Ir->Up or 
	Ir->Dn or
	Ir->Power or
	Ir->Enter or
	Ir->Select =>
		return 1;
	* =>
		return 0;
	}
}

canmove(player: int) : int
{
	i, j: int;
        
        for (i = 0; i < M ; i++)
                for (j = 0; j < M; j++) 
			if (contents[i][j] == Empty) 
				if(checkforflips(1,i,j,player))
					return 1;
	return 0;
}

# one round, either you or opponent
makemove(player: int, g: Game, irc: chan of int) : int
{
	color: ref Image;
	kn: int;

	pos := (M - 1) / 2;
	row := (M - 1) / 2;

	if (player == PlayWhite)
		color = white;
	else
		color = black;

	ring(pos, row);

loop:	for (;;) {
#		if (player == iam) {
			do
				kn = <- irc;
			while (!goodmove(kn));
			g.Out(kn);
#		} else {
#			kn = g.In();
#		}
		case kn {
		Ir->Dn =>
			unring(pos, row);
			row++;
			if (row == M)
				row = 0;
			ring(pos, row);
			cleartext();
		Ir->Up =>
			unring(pos, row);
			row--;
			if (row < 0)
				row  = M - 1;
			ring(pos, row);
			cleartext();
		Ir->FF =>
			unring(pos, row);
			pos++;
			if (pos == M)
				pos = 0;
			ring(pos, row);
			cleartext();
		Ir->Rew =>
			unring(pos, row);
			pos--;
			if (pos < 0)
				pos = M - 1;
			ring(pos, row);
			cleartext();
		Ir->Power or Ir->Enter =>
			outcome(player != iam, "Forfeit");
			break loop;
		Ir->Select =>
			if (contents[pos][row] == Empty) {
				if(checkforflips(0,pos,row,player))
				{
					puck(pos, row, color);
					contents[pos][row] = player;
					return 0;
				}
			}
			disptext("can't place stone there");
		}
	}
	return 1;
}

checkforflips(justtesting,pos, row, player: int) : int
{
	i, j, good: int;

	good=0;

	for(i = -1; i<2; i++)
		for(j = -1; j<2; j++)
			good|=check(justtesting,i,j,pos,row,player);
	
	return good;
}

check(justtesting,xvector,yvector,pos,row,player: int) : int
{
	i, j: int;

	if(xvector == 0 && yvector == 0)
		return 0;

	i=pos+xvector;
	j=row+yvector;
	while(i<M && j<M && i>-1 && j>-1)
	{
		#sys->fprint(stderr, "checking %d,%d %d,%d \n",i ,j, pos,row);
		if(contents[i][j] == Empty)
			return 0;

		if(contents[i][j] == player)
			return flipthem(justtesting,pos,i,xvector,row,j,yvector,player);
		
		i+=xvector; j+=yvector;
	}
	return 0;
}

flipthem(justtesting,startx, endx, dirx, starty, endy, diry, player: int) : int
{
	i, j, atleastone: int;
	color: ref Image;

	atleastone=0;
	if(player == PlayWhite)
                color = white;
        else
                color = black;

	i=startx+=dirx; 
	j=starty+=diry;
	while(!(i==endx && j==endy))
	{
		if(!justtesting)
		{
			#sys->fprint(stderr, "flip %d,%d\n",i,j);
			contents[i][j] = player;
			spawn spinpuck(i, j, color);
			sys->sleep(100);
		}
		i+=dirx; j+=diry;
		atleastone=1;
	}
	return atleastone;
}

# check if the player that just moved has won
winner() : int
{
	i, j: int;
	blackcnt, whitecnt: int;

	blackcnt =0;
	whitecnt =0;
	for (i = 0; i < M-1 ; i++)
		for (j = 0; j < M-1; j++) {
			if (contents[i][j] == PlayWhite )
				whitecnt++;
			else
				blackcnt++;
		}
	if(whitecnt>blackcnt)
		disptext("white won");
	else if(blackcnt>whitecnt)
		disptext("black won");
	else
		disptext("tie");
	sys->sleep(10000);
	return 0;
}

# clear the text rectangle
cleartext()
{
	disp.draw(TX, back, nil, (0, 0));
}

# display a string in the text rectangle
disptext(s: string)
{
	disp.text(TX.min.add((TOFFX, TOFFY)), textcol, (0, 0), textfont, s);
}

# display a string in the text rectangle
disptext0(s: string)
{
	disp.text(TX0.min.add((TOFFX, TOFFY)), textcol, (0, 0), textfont, s);
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

# circle routine, for pucks 
circle(x, y, r: int, c: ref Image)
{
	disp.fillellipse(TC.add((A + x * C, A + y * C)), r, r, c, (0, 0));
}

# ellispe routine, for edge of stones
ellispe(x, y, r: int, c: ref Image, factor: int)
{
	puck(x,y,hole);
	disp.fillellipse(TC.add((A + x * C, A + y * C)), r, r/factor,
	c, (0, 0));
}


# draw a played piece
puck(x, y: int, c: ref Image)
{
	circle(x, y, R, c);
}

# place a played piece
spinpuck(x, y: int, c: ref Image)
{
	sleepytime: int;

	sleepytime=10;
	while(sleepytime<250)
	{
	 	circle(x, y, R, black);
		sys->sleep(sleepytime);
	 	ellispe(x, y, R, black,2);
		sys->sleep(sleepytime*2);
	 	ellispe(x, y, R, black,3);
		sys->sleep(sleepytime);
	 	ellispe(x, y, R, white,3);
		sys->sleep(sleepytime/2);
	 	ellispe(x, y, R, white,2);
		sys->sleep(sleepytime);
	 	circle(x, y, R, white);
		sys->sleep(sleepytime);
		sleepytime *= 2;
	}
	circle(x, y, R, c);
}

# draw a potential move 
ring(x, y: int)
{
	oldcolor: ref Image;

	if (contents[x][y] == Empty) 
		oldcolor = hole;
	else if (contents[x][y] == PlayWhite)
		oldcolor = white;
	else
		oldcolor = black;
	
	circle(x, y, R, red);
        circle(x, y, R - 4, oldcolor);
}

# erase a potential move 
unring(x, y: int)
{
	oldcolor: ref Image;

	if (contents[x][y] == Empty) 
		oldcolor = hole;
	else if (contents[x][y] == PlayWhite)
		oldcolor = white;
	else
		oldcolor = black;
        circle(x, y, R , oldcolor);
}
