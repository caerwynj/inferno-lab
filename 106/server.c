#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include "rudp.h"

#define BUFLEN 512
#define NPACK 10
#define PORT 9930

void diep(char *s)
{
    perror(s);
    exit(1);
}

int main(void)
{
    struct sockaddr_in si_other;
    int i;
    unsigned int slen = sizeof(si_other);
    char buf[BUFLEN];
    struct Rudp_sock *rs;
    int len;

    if((rs = rudp_announce(PORT)) == NULL)
	diep("rudp_announce");

    for (i = 0; i < NPACK; i++) {
	if ((len = rudp_recvfrom(rs, buf, BUFLEN, 0, 
			(struct sockaddr *)&si_other, &slen)) == -1)
	    diep("rudp_recvfrom");
	printf("Received packet from %s:%d\nData: %s\n\n",
	       inet_ntoa(si_other.sin_addr), ntohs(si_other.sin_port),
	       buf);
        if (rudp_sendto(rs, buf, len, 0) == -1)
		diep("response failed\n");
    }

    rudp_close(rs);
    return 0;
}
