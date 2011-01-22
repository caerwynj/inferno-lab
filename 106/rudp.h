/* RUDP */
/* Header bits copied from Inferno (c) Vitanuova */
/* this is a single threaded implementation */

#include <sys/types.h>          /* See NOTES */
#include <sys/socket.h>

typedef struct Rudp_block Rudp_block;
struct Rudp_block {
	void *buf;
	size_t len;
	int flag;
	
	Rudp_block *next;
};

typedef struct Rudp_sock Rudp_sock;
struct Rudp_sock {
	int fd;		/* underlyng sock_fd */

	struct sockaddr *addr;
	socklen_t addrlen;	

	/* window */
	Rudp_block *unacked; /* unacked msg list */
	Rudp_block *unackedtail; /* and its tail */
	
	int timeout;	/* time since first unacked msg sent (for backoff) */
	int xmits;	/* number of time first unacked msg sent */

	unsigned long sndseq;	/* next packet to be sent */
	unsigned long sndgen;	/*  and its generation */
	
	unsigned long rcvseq;	/* last packet received */
	unsigned long rcvgen;	/*  and its generation */

	unsigned long acksent;  /* last ack sent */
	unsigned long ackrcvd;  /* last ack recvied */
};

Rudp_sock *rudp_announce(int);
Rudp_sock *rudp_connect(const struct sockaddr *, socklen_t);

ssize_t rudp_sendto(Rudp_sock *, const void *, size_t, int);
                      
ssize_t rudp_recvfrom(Rudp_sock *, void *, size_t, int,
                        struct sockaddr *, socklen_t *);
void rudp_close(Rudp_sock *rs);
