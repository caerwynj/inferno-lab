/* 
 * Simple RUDP Implementation 
 * Copyright © 2010 Eric Van Hensbergen.  All rights reserved.
 */

/* 
  This code based on rudp.c from Inferno distribution
        Copyright © 1994-1999 Lucent Technologies Inc.  All rights reserved.
        Portions Copyright © 1997-1999 Vita Nuova Limited
        Portions Copyright © 2000-2007 Vita Nuova Holdings Limited 
                                       (www.vitanuova.com)
        Revisions Copyright © 2000-2007 Lucent Technologies Inc. and others

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#include "rudp.h"
#include <stdlib.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <sys/select.h>

#define SEQDIFF(a,b) ( (a)>=(b)?\
                        (a)-(b):\
                        0xffffffffUL-((b)-(a)) )
#define INSEQ(a,start,end) ( (start)<=(end)?\
                                ((a)>(start)&&(a)<=(end)):\
                                ((a)>(start)||(a)<=(end)) )
#define UNACKED(r) SEQDIFF(r->sndseq, r->ackrcvd)
#define NEXTSEQ(a) ( (a)+1 == 0 ? 1 : (a)+1 )

unsigned long generation = 0;

#define DEBUG 0
#define DPRINT if(DEBUG)printf

enum
{
	RUDP_HDR_SZ	= 16,

        Rudprxms        = 200,
        Rudptickms      = 50,
        Rudpmaxxmit     = 10,
        Maxunacked      = 100,

	Hangupgen	= 0xffffffff,
};

struct Rudphdr
{
	uint32_t relseq;
	uint32_t relsgen;
	uint32_t relack;
	uint32_t relagen;
};

void
rudp_hangup(Rudp_sock *rs)
{
	Rudp_block *rb;

	while(rs->unacked != NULL) {
		rb = rs->unacked;
		rs->unacked = rb->next;
		free(rb);
	}

	rs->rcvgen = 0;
	rs->rcvseq = 0;
	rs->acksent = 0;
	if(generation == Hangupgen)
		generation++;
        rs->sndgen = generation++;
        rs->sndseq = 0;
        rs->ackrcvd = 0;
        rs->xmits = 0;
        rs->timeout = 0;
}

/* retransmit first block on the unacked list */
int
rudp_rexmit(Rudp_sock *rs)
{
	
	rs->timeout = 0;
	if(rs->xmits++ > Rudpmaxxmit){
		perror("hangup");
		rudp_hangup(rs);
		return -1;
	}

	DPRINT("rxmit rs->ackrcvd+1 = %lu\n", rs->ackrcvd+1);
	return sendto(rs->fd, rs->unacked->buf, rs->unacked->len, 
			rs->unacked->flag, rs->addr, rs->addrlen);
}

void
rudp_sendack(Rudp_sock *rs, int hangup)
{
	char *rudp_pkt = malloc(RUDP_HDR_SZ);
	struct Rudphdr *hdr = (struct Rudphdr *)rudp_pkt;

	if(rudp_pkt == NULL)
		return;

	memset(rudp_pkt, 0, RUDP_HDR_SZ);

	hdr->relseq = htonl(0);
	if(hangup)
		hdr->relsgen = Hangupgen;
	else
		hdr->relsgen = htonl(rs->sndgen);
	hdr->relack = htonl(rs->rcvseq);
	hdr->relagen = htonl(rs->rcvgen);

	if(rs->acksent < rs->rcvseq)
		rs->acksent = rs->rcvseq;
	
	sendto(rs->fd, rudp_pkt, RUDP_HDR_SZ, 0, rs->addr, rs->addrlen);
}

static ssize_t
rudp_recv(Rudp_sock *rs, void *buf, size_t len, int flag,
		struct sockaddr *sa, socklen_t *salen)
{
	fd_set readfds;
	struct timeval timeout;
	int ret;
	int err;

	/* 
         * we are about to block, so if there are any unacked
	 * messages, we should go ahead and take care of that 
         *
	 */
	if(rs->acksent != rs->rcvseq)
		rudp_sendack(rs, 0);
again:
	timeout.tv_sec = 1;
	timeout.tv_usec = 0;
	FD_ZERO(&readfds);
	FD_SET(rs->fd, &readfds);
	ret = select(rs->fd+1, &readfds, NULL, NULL, &timeout);	
	if(ret < 0) {
		perror("select");
		exit(1);
	}

	/* FIXME: doesn't account for giving up */
	if((ret == 0)&&(rs->unacked)) {
		err = rudp_rexmit(rs);
		if(err < 0)
			return err;
		goto again;
	}
	
	err = recvfrom(rs->fd, buf, len, flag, sa, salen);
	return err;	
}

static void
rudp_ackq(Rudp_sock *rs, void *buf, size_t len, int flag)
{
	Rudp_block *blk = malloc(sizeof(struct Rudp_block));
	if(blk == NULL) {
		perror("out of memeory\n");
		exit(1);
	}
	memset(blk, 0, sizeof(struct Rudp_block));

	blk->buf = buf;
	blk->len = len;
	if(rs->unacked)
		rs->unackedtail->next = blk;
	else {
		rs->timeout = 0;
		rs->xmits = 1;
		rs->unacked = blk;	
	}
	rs->unackedtail = blk;
}

static Rudp_sock *
rudp_socket(void)
{
	Rudp_sock *rs = malloc(sizeof(struct Rudp_sock));

	if(rs == NULL)
		return NULL;

	memset(rs, 0, sizeof(Rudp_sock));
	if((rs->fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)) == -1)
		goto free_and_retnull;

	while(generation == 0) {
		srandom(getpid());
		generation = random();
	}

	rs->sndgen = generation++;

	return rs;

free_and_retnull:
	free(rs);
	return NULL;
}

/* listen end */
Rudp_sock *
rudp_announce(int port)
{
	struct sockaddr_in addr;
	Rudp_sock *rs = rudp_socket();

	if(rs == NULL)
		return NULL;

	memset((void *) &addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);

	if(bind(rs->fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
		close(rs->fd);
		goto free_and_retnull;
	}

	return rs;

free_and_retnull:
	free(rs);
	return NULL;
}

struct Rudp_sock *
rudp_connect(const struct sockaddr *addr, socklen_t addrlen)
{
	Rudp_sock *rs = rudp_socket();

	
	if(rs == NULL)
		return NULL;

	rs->addr = malloc(addrlen);
	if(rs->addr == NULL)
		goto free_and_close;

	memcpy(rs->addr, addr, addrlen);
	rs->addrlen = addrlen;


	return rs;

free_and_close:
	close(rs->fd);
	free(rs);
	return NULL;
}

ssize_t 
rudp_sendto(Rudp_sock *rs, const void *buf, size_t len, int flag)
{
	char *rudp_pkt = malloc(len+RUDP_HDR_SZ);
	struct Rudphdr *hdr = (struct Rudphdr *)rudp_pkt;


	if(rudp_pkt == NULL)
		return -1;
	memset(rudp_pkt, 0, RUDP_HDR_SZ);

	rs->sndseq = NEXTSEQ(rs->sndseq);
	hdr->relseq = htonl(rs->sndseq);
	hdr->relsgen = htonl(rs->sndgen);
	hdr->relack = htonl(rs->rcvseq);
	hdr->relagen = htonl(rs->rcvgen);
	
	if(rs->rcvseq != rs->acksent)
		rs->acksent = rs->rcvseq;

	DPRINT("sent: %lu/%lu, %lu/%lu\n",
                rs->sndseq, rs->sndgen, rs->rcvseq, rs->rcvgen);

	memcpy(rudp_pkt+RUDP_HDR_SZ, buf, len);	

	rudp_ackq(rs, rudp_pkt, len+RUDP_HDR_SZ, flag);

	return sendto(rs->fd, rudp_pkt, len+RUDP_HDR_SZ, flag, 
						rs->addr, rs->addrlen);
}

ssize_t 
rudp_recvfrom(Rudp_sock *rs, void *buf, size_t len, int flag, 
				struct sockaddr *addr, socklen_t *addrlen)
{
	int err;
	unsigned long seq, ack, sgen, agen, ackreal;
	char *rudp_pkt = malloc(len+RUDP_HDR_SZ);
	struct Rudphdr *hdr = (struct Rudphdr *)rudp_pkt;
	struct Rudp_block *rb;
	struct sockaddr_in myaddr;
	unsigned int myaddrlen = sizeof(myaddr);

	if(rudp_pkt == NULL) {
		perror("out of memory");
		return -1;
	}
	memset(rudp_pkt, 0, RUDP_HDR_SZ);

again:
	err = rudp_recv(rs, rudp_pkt, len+RUDP_HDR_SZ, flag, 
			(struct sockaddr *)&myaddr, (socklen_t *) &myaddrlen);

	if(addr != NULL)
		memcpy(addr, &myaddr, myaddrlen);
	if(addrlen != NULL)
		*addrlen = myaddrlen;

	seq = ntohl(hdr->relseq);
	sgen = ntohl(hdr->relsgen);
	ack = ntohl(hdr->relack);
	agen = ntohl(hdr->relagen);

	DPRINT("rcvd %lu/%lu, %lu/%lu, rs->sndgen = %lu\n",
			seq, sgen, ack, agen, rs->sndgen);


	/* if acking an incorrect generation, ignore */
	if(ack && agen != rs->sndgen)
		goto again;

	/* look for a hangup */
	if(sgen == Hangupgen) {
		DPRINT("HANGUP\n");
		if(agen == rs->sndgen) {
			rudp_hangup(rs);
		}
		perror("hungup");
		return -1;
	}
	
	/* make sure we are not talking to a new remote side */
	if(rs->rcvgen != sgen) {
		if(seq !=0 && seq != 1)
			goto again;

		if(rs->rcvgen != 0) {
			DPRINT("NEW REMOTE SIDE\n");
			rudp_hangup(rs);
		}
		if(rs->addr != NULL)
			free(rs->addr);
		rs->addr = malloc(myaddrlen);
		memcpy(rs->addr, &myaddr, myaddrlen);
		rs->addrlen = myaddrlen;

		rs->rcvgen = sgen;
	}

	/* dequeue acked packets */
	if(ack && agen == rs->sndgen) {
		ackreal = 0;
		while(rs->unacked != NULL && 
			INSEQ(ack, rs->ackrcvd, rs->sndseq)) {
			rb = rs->unacked;
			rs->unacked = rb->next;
			free(rb);
			rs->ackrcvd = NEXTSEQ(rs->ackrcvd);
			ackreal = 1;
		}
	
		/* 
		 * retransmit next packet if the acked packet
		 * was transmitted more than once
		 */
		if(ackreal && rs->unacked != NULL) {
			rs->timeout = 0;
			if(rs->xmits > 1) {
				int rxerr;
				rs->xmits = 1;
				rxerr = rudp_rexmit(rs);
				if(rxerr < 0)
					return rxerr;
			}
		}
	}
		
	/* no message or input queue full? */
	if(seq == 0)
		goto again;
	
	/* refuse out of order delivery */
	if(seq != NEXTSEQ(rs->rcvseq)){
		/* tell him we got it already */
		rudp_sendack(rs, 0); 
		goto again;
	}

	rs->rcvseq = seq;
	/* only copy if we got this far without error */
	if(err > RUDP_HDR_SZ) {
		memcpy(buf, rudp_pkt+RUDP_HDR_SZ, err-RUDP_HDR_SZ);	
	}

	return err;
}

void
rudp_close(Rudp_sock *rs)
{
	if(rs->acksent != rs->rcvseq)
		rudp_sendack(rs, 0);
	close(rs->fd);
	free(rs->addr);
	free(rs);
}

