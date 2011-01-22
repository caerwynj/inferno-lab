#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#define NELEM(a) ((sizeof a)/(sizeof a[0]))

int
main (int argc, char *argv[]){
	int i, *s1, *s2;
	int ksizes[] = {32, 64, 128, 256, 512, 1024, 2048, 4096};

	i=0;
	if (argc > 1)
		i = atoi(argv[1]);
	if (i < 0 || i >= NELEM(ksizes))
		return -1;

	s1 = malloc (ksizes[i]*1024);
	s2 = malloc (ksizes[i]*1024);
	printf ("m total: %dKB\n", 2*ksizes[i]);
	printf ("m: alloc start: %d, end: %d, size %d\n", s1, s1+2*ksizes[i], 2*ksizes[i]*1024);
	printf ("m1: alloc start: %d, end: %d, size %d\n", s1, s1+ksizes[i]*1024, ksizes[i]*1024);
	printf ("m2: alloc start: %d, end: %d, size %d\n", s2, s2+ksizes[i]*1024, ksizes[i]*1024);
	
	if (s1 != NULL)
		free(s1);
	if (s2 != NULL)
		free(s2);
}
