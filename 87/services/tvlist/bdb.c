/*
 * All units in quarter hours (including dates)
 */
#include <lib9.h>
#include <bio.h>

enum
{
	NCHAN = 128,
};

typedef struct Chan Chan;
struct Chan
{
	char	name[128];
	int	fd;
};
int nchan;
Chan chan[NCHAN];

Chan*
getchan(char *name)
{
	int i;
	Chan *c;

	for(i = 0; i < nchan; i++)
		if(strcmp(chan[i].name, name) == 0)
			return &chan[i];

	print("%s\n", name);

	c = &chan[nchan++];
	strcpy(c->name, name);
	c->fd = create(name, OWRITE, 0666);
	if(c->fd < 0) {
		fprint(2, "failed to create %s: %r\n", name);
		exits("create");
	}
	return c;
}

int
time2quart(char *t)
{
	int mins, hrs, qrt;

	if(strlen(t) != 4)
		fprint(2, "bad time\n");

	mins = strtoul(t+2, 0, 10);
	t[2] = '\0';
	hrs = strtoul(t, 0, 10);
	qrt = (hrs*4) + (mins/15);
/*	print("mins %d hrs %d quart %d\n", mins, hrs, qrt); */

	return qrt;
}

char	days[] =
{
	0,
	31, 29, 31, 30,
	31, 30, 31, 31,
	30, 31, 30, 31,
};

/* 19950907 */
int
date2quart(char *xt)
{
	char t[32];
	int year, month, day, qrt;

	strncpy(t, xt, sizeof(t));
	if(strlen(t) != 8)
		fprint(2, "bad date: %s\n", t);

	day = strtoul(t+6, 0, 10);
	t[6] = '\0';
	month = strtoul(t+4, 0, 10);
	t[4] = '\0';
	year = strtoul(t, 0, 10);

	if(year < 1994 || month < 1 || month > 12 || day < 1 || day > 31)
		fprint(2, "bad date\n");

	qrt = (year*365*24*4) + days[month]*24*4 + day*24*4;

/*	print("year %d month %d day %d quart %d\n", year, month, day, qrt); */

	return qrt; 
}

void
main(int argc, char *argv[])
{
	char *p;
	Biobuf *bp;
	Chan *C;
	char *av[64];
	uchar *xp, *up;
	int fa, i, posn, date, c, n, len, start, durat, first, base;

	if(argc != 2) {
		fprint(2, "usage: dbd tms.feed\n");
		exits("usage");
	}

	bp = Bopen(argv[1], OREAD);
	if(bp == 0) {
		fprint(2, "dbd: open %s: %r\n", argv[1]);
		exits("open");
	}

	setfields("|\n");

	xp = (uchar *)0;
	first = 0;
	for(;;) {

		posn = Bseek(bp, 0, 1);
		p = Brdline(bp, '\n');
		if(p == 0)
			break;
		p[Blinelen(bp) - 1] = 0;

		/* 
			Shri - First line of the feed file is dummy line
			to get the base date (start date of the guide).
		*/
          	n = getfields(p, av, nelem(av));
		if(n != 25) {
			fprint(2, "Malformed record ignored\n'%s'\n", p);
			continue;
		}

		/*posn = Bseek(bp, 0, 1);*/

		if(!first) {
			base = date2quart(av[3]);
			print("base date %s=%d\n", av[3], base);
			first = 1;
			posn = Bseek(bp, 0, 1);
			p = Brdline(bp, '\n');
			if(p == 0)
				break;
			p[Blinelen(bp) - 1] = 0;
          		n = getfields(p, av, nelem(av));
			if(n != 25) {
				fprint(2, "Malformed record ignored\n'%s'\n", p);
				continue;
			}
		}

		/* Find the channel */
		C = getchan(av[2]);

		start = time2quart(av[4]);
		durat = time2quart(av[5]);
		date = date2quart(av[3]) - base;
		if(date < 0)
			fprint(2, "negative date %s\n", av[3]);

		fa = (date + start) * 4;
		if(seek(C->fd, fa, 0) != fa)
			fprint(2, "index seek error %s/%d: %r\n", C->name, fa);

		xp = realloc(xp, durat*4);
		up = xp;
		for(i = 0; i < durat; i++) {
			up[0] = posn>>24;
			up[1] = posn>>16;
			up[2] = posn>>8;
			up[3] = posn;
			up += 4;
		}
		if(write(C->fd, xp, durat*4) != durat*4)
			fprint(2, "index write error %s: %r\n", C->name);
	}
}
