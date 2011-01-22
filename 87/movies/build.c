#include "lib9.h"

enum
{
	BUFSIZE		= 10*1024*1024
};
#define nelem(x)	(sizeof(x)/sizeof(x[0]))

typedef struct Category Category;
struct Category
{
	char	name[32];
	char	index;
	int	posn;
	int	tfd;		/* Title Index */
	int	ifd;		/* Data Base pointers */
} category[] = {
	{"Drama", 'A' },
	{"Comedy", 'A' },
	{"Action", 'A' },
	{"Horror", 'A' },
	{"Mystery", 'A' },
	{"Musical", 'A' },
	{"Western", 'A' },
	{"Sci-Fi", 'A' }
};

void
mapit(char *t)
{
	while(*t) {
		while(*t && (*t < 'A' || *t > 'Z'))
			t++;
		if(*t == '\0')
			break;
		t++;
		while(*t && ((*t >= 'A' && *t <= 'Z') || *t == '\'')) {
			if(*t >= 'A' && *t <= 'Z')
				*t += 'a' - 'A';
			t++;
		}
		if(strncmp(t-3, "Iii", 3) == 0)
			strncpy(t-3, "III", 3);
		if(strncmp(t-2, "Ii", 2) == 0)
			strncpy(t-2, "II", 2);
		if(strncmp(t-2, "Iv", 2) == 0)
			strncpy(t-2, "IV", 2);
		if(strncmp(t-2, "Vi", 2) == 0)
			strncpy(t-2, "VI", 2);
		if(strncmp(t-3, "Vii", 3) == 0)
			strncpy(t-3, "VII", 3);
		if(strncmp(t-2, "Th", 2) == 0)
			strncpy(t-2, "th", 2);
	}
}

void
main(void)
{
	int i, n, fd, nmovies;
	ulong l, mpeg, trailer;
	char *adds, *catez, *synopez, idx[32];
	char *buf, *start, *cat, *synop, *z, *t, *ez;

	fd = open("database", OREAD);
	if(fd < 0) {
		fprint(2, "cant open database: %r\n");
		exit(1);
	}

	buf = malloc(BUFSIZE);
	if(buf == 0) {
		fprint(2, "malloc failed\n");
		exit(1);
	}
	
	n = read(fd, buf, BUFSIZE);
	if(n < 0) {
		fprint(2, "read database: %r\n");
		exit(1);
	}
	if(n >= BUFSIZE) {
		fprint(2, "BUFSIZE too small: %r\n");
		exit(1);
	}
	close(fd);

	buf[n] = '\0';

	fprint(2, "read %d bytes\n", n);

	for(i = 0; i < nelem(category); i++) {
		fd = open(category[i].name, O_WRONLY|O_CREAT|O_TRUNC, 0666);
		if(fd < 0) {
			fprint(2, "create category %s: %r\n", category[i].name);
			exit(1);
		}
		category[i].tfd = fd;
		sprint(idx, "%s.idx", category[i].name);
		fd = open(idx, O_WRONLY|O_CREAT|O_TRUNC, 0666);
		if(fd < 0) {
			fprint(2, "create category %s.idx: %r\n", category[i].name);
			exit(1);
		}
		category[i].ifd = fd;
	}

	start = buf;
	nmovies = 0;
	for(;;) {
		mpeg = 0;
		trailer = 0;

		start = strstr(start+1, "Title:");
		if(start == 0)
			break;
		cat = strstr(start+1, "Category:");
		if(cat == 0)
			break;
		catez = strchr(cat, '\n');
		if(catez == 0)
			break;
		synop = strstr(start+1, "Synopsis:");
		if(synop == 0)
			break;
		synopez = strchr(synop, '\n');
		if(synopez == 0)
			break;

		adds = synopez+1;
		for(;;) {
			if(*adds == '\n')
				break;
			if(strncmp(adds, "Movie:", 6) == 0) {
				adds += 7;
				while(*adds && (*adds == '\t' || *adds == ' '))
					adds++;
				mpeg = adds - buf;
			}
			else
			if(strncmp(adds, "Trailer:", 8) == 0) {
				adds += 9;
				while(*adds && (*adds == '\t' || *adds == ' '))
					adds++;
				trailer = adds - buf;
			}
			while(*adds && *adds != '\n')
				adds++;
			adds++;
		}

		for(i = 0; i < nelem(category); i++) {
			z = strstr(cat, category[i].name);
			if(z != 0 && z < catez) {
				t = start+7;
				while(*t && (*t == ' ' || *t == '\t'))
					t++;
				ez = strchr(t, '\n');
				if(ez == 0)
					break;
				ez[0] = '\0';

				mapit(t);

				fprint(category[i].tfd, "%s\n", t);

				memset(idx, 0, sizeof(idx));

				l = ez+1-buf;		/* Information Start */
				idx[0] = l>>24;
				idx[1] = l>>16;
				idx[2] = l>>8;
				idx[3] = l>>0;

				l = synopez-buf+1;	/* Information Len */
				l -= (ez+1-buf);
				idx[4] = l>>24;
				idx[5] = l>>16;
				idx[6] = l>>8;
				idx[7] = l>>0;

				l = mpeg;		/* MPEG Movie Start */
				idx[8] = l>>24;
				idx[9] = l>>16;
				idx[10] = l>>8;
				idx[11] = l>>0;

				l = trailer;		/* MPEG Trailer Start */
				idx[12] = l>>24;
				idx[13] = l>>16;
				idx[14] = l>>8;
				idx[15] = l>>0;

				if(write(category[i].ifd, idx, 16) != 16) {
					fprint(2, "write .idx: %r\n");
					exit(1);
				}

				nmovies++;
				ez[0] = '\n';
			}
		}
	}
	fprint(2, "read %d movies\n", nmovies);
}
