#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include "rudp.h"

#define BUFLEN 512
#define NPACK 10
#define PORT 9930
#define SRV_IP "127.0.0.1"

void diep(char *s)
{
    perror(s);
    exit(1);
}

int main(void)
{
    Rudp_sock *rs;
    struct sockaddr_in si_other;
    int i, slen = sizeof(si_other);
    char buf[BUFLEN];
   
    memset((void*) &si_other, 0, sizeof(si_other));
    si_other.sin_family = AF_INET;
    si_other.sin_port = htons(PORT);
    if (inet_aton(SRV_IP, &si_other.sin_addr) == 0) {
	fprintf(stderr, "inet_aton() failed\n");
	exit(1);
    }

    if ((rs = rudp_connect((struct sockaddr *)&si_other, slen)) == NULL)
	diep("rudp_connect");

    for (i = 0; i < NPACK; i++) {
	printf("Sending packet %d\n", i);
	sprintf(buf, "This is packet %d\n", i);
	if (rudp_sendto(rs, buf, BUFLEN, 0) == -1)
	    diep("rudp_sendto()");
	printf("Waiting on recv\n");
	if (rudp_recvfrom(rs, buf, BUFLEN, 0, NULL, NULL) == -1)
	    diep("rudp_recvfrom\n");
	printf("Received response %s\n", buf);
    }

    rudp_close(rs);
    return 0;
}
