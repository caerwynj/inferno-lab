#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#define NELEM(a) ((sizeof a)/(sizeof a[0]))

int
main (int argc, char *argv[]){
	int i, *p;
	int ksizes[] = {32, 64, 128, 256, 512, 1024, 2048, 4096};

	i=0;
	if (argc > 1)
		i = atoi(argv[1]);
	if (i < 0 || i >= NELEM(ksizes))
		return -1;

	p = malloc (ksizes[i]*1024);
	printf ("alloc start: %d, size %dKB\n", p, ksizes[i]);
	if (p != NULL)
		free(p);
}
