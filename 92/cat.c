#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

void
cat(int f, char *s)
{
	char buf[8192];
	long n;

	while((n=read(f, buf, (long)sizeof buf))>0)
		if(write(1, buf, n)!=n){
			fprintf(stderr, "write error copying %s: %r", s);
			exit(1);
		}
	if(n < 0)
		exit(1);
}

int
main(int argc, char *argv[])
{
	int f, i;

	if(argc == 1)
		cat(0, "<stdin>");
	else for(i=1; i<argc; i++){
		f = open(argv[i], 0);
		if(f < 0)
			exit(1);
		else{
			cat(f, argv[i]);
			close(f);
		}
	}
}
