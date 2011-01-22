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
main(void)
{
	ulong l;
	char *buf, *p, xx[128];
	int o, i, n, fd, z, idx, warp[26];

	buf = malloc(BUFSIZE);
	if(buf == 0) {
		fprint(2, "malloc failed\n");
		exit(1);
	}

	for(i = 0; i < nelem(category); i++) {
		sprint(xx, "%s.warp", category[i].name);

		fd = open(category[i].name, O_RDONLY);
		n = read(fd, buf, BUFSIZE);
		if(n < 0) {
			fprint(2, "read %s: %r\n", category[i].name);
			exit(1);
		}
		if(n >= BUFSIZE) {
			fprint(2, "BUFSIZE too small: %r\n");
			exit(1);
		}
		close(fd);
		buf[n] = '\0';

		fprint(2, "%s: read %d bytes\n", category[i].name, n);

		idx = 0;
		z = 'A';
		p = buf;
		memset(warp, 0, sizeof(warp));
		for(;;) {
			if(strncmp("The ", p, 4) == 0)
				p += 4;
			if(strncmp("An ", p, 3) == 0)
				p += 3;
			if(strncmp("A ", p, 2) == 0)
				p += 2;
			if(p[0] >= z+1) {
				o = p[0]-'A';
				warp[o] = idx;
				for(n = o+1; n < 26; n++)
					warp[n] = idx;
/*				fprint(2, "%c -> %c %d\n", z, p[0], idx); */
				z++;
			}
			idx++;
			p = strchr(p, '\n');
			if(p == 0)
				break;
			p++;
		}
		fd = open(xx, O_WRONLY|O_CREAT|O_TRUNC, 0666);
		if(fd < 0) {
			fprint(2, "create category %s.idx: %r\n", category[i].name);
			exit(1);
		}
		for(n = 0; n < 26; n++) {
			l = warp[n];
			xx[0] = l>>24;
			xx[1] = l>>16;
			xx[2] = l>>8;
			xx[3] = l>>0;
			write(fd, xx, 4);
		}
		close(fd);
	}
}
