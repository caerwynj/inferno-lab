#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"version.h"
#include	"libcrypt.h"
#include	"keyboard.h"

extern int cflag;
int	exdebug;
extern int keepbroken;

enum
{
	Qdir,
	Qcons,
	Qconsctl,
	Qdrivers,
	Qhostowner,
	Qhoststdin,
	Qhoststdout,
	Qhoststderr,
	Qjit,
	Qkeyboard,
	Qkprint,
	Qmemory,
	Qmsec,
	Qnotquiterandom,
	Qnull,
	Qpin,
	Qpointer,
	Qrandom,
	Qscancode,
	Qsnarf,
	Qsysctl,
	Qsysname,
	Qtime,
	Quser
};

enum {
	SnarfSize = 64*1024
};

Dirtab contab[] =
{
	".",	{Qdir, 0, QTDIR},	0,		DMDIR|0555,
	"cons",		{Qcons},	0,	0666,
	"consctl",	{Qconsctl},	0,	0222,
	"drivers",	{Qdrivers},	0,	0444,
	"hostowner",	{Qhostowner},	0,	0644,
	"hoststdin",	{Qhoststdin},	0,	0444,
	"hoststdout",	{Qhoststdout},	0,	0222,
	"hoststderr",	{Qhoststderr},	0,	0222,
	"jit",	{Qjit},	0,	0666,
	"keyboard",	{Qkeyboard},	0,	0666,
	"kprint",	{Qkprint},	0,	0444,
	"memory",	{Qmemory},	0,	0444,
	"msec",		{Qmsec},	NUMSIZE,	0444,
	"notquiterandom",	{Qnotquiterandom},	0,	0444,
	"null",		{Qnull},	0,	0666,
	"pin",		{Qpin},		0,	0666,
	"pointer",	{Qpointer},	0,	0666,
	"random",	{Qrandom},	0,	0444,
	"scancode",	{Qscancode},	0,	0444,
	"snarf",	{Qsnarf},	0,		0666,
	"sysctl",	{Qsysctl},	0,	0644,
	"sysname",	{Qsysname},	0,	0644,
	"time",		{Qtime},	0,	0644,
	"user",		{Quser},	0,	0644,
};

Dirtab *snarftab = &contab[19];

Queue*	gkscanq;		/* Graphics keyboard raw scancodes */
char*	gkscanid;		/* name of raw scan format (if defined) */
Queue*	gkbdq;			/* Graphics keyboard unprocessed input */
Queue*	kbdq;			/* Console window unprocessed keyboard input */
Queue*	lineq;			/* processed console input */

char	*ossysname;

static struct
{
	RWlock l;
	Queue*	q;
} kprintq;

vlong	timeoffset;

extern int	dflag;

static int	sysconwrite(void*, ulong);
extern char**	rebootargv;

static struct
{
	QLock	q;
	QLock	gq;		/* separate lock for the graphical input */

	int	raw;		/* true if we shouldn't process input */
	Ref	ctl;		/* number of opens to the control file */
	Ref	ptr;		/* number of opens to the ptr file */
	int	scan;		/* true if reading raw scancodes */
	int	x;		/* index into line */
	char	line[1024];	/* current input line */

	Rune	c;
	int	count;
} kbd;

void
kbdslave(void *a)
{
	char b;

	USED(a);
	for(;;) {
		b = readkbd();
		if(kbd.raw == 0)
			write(1, &b, 1);
		qproduce(kbdq, &b, 1);
	}
	pexit("kbdslave", 0);
}

void
gkbdputc(Queue *q, int ch)
{
	int n;
	Rune r;
	static uchar kc[5*UTFmax];
	static int nk, collecting = 0;
	char buf[UTFmax];

	r = ch;
	if(r == Latin) {
		collecting = 1;
		nk = 0;
		return;
	}
	if(collecting) {
		int c;
		nk += runetochar((char*)&kc[nk], &r);
		c = latin1(kc, nk);
		if(c < -1)	/* need more keystrokes */
			return;
		collecting = 0;
		if(c == -1) {	/* invalid sequence */
			qproduce(q, kc, nk);
			return;
		}
		r = (Rune)c;
	}
	n = runetochar(buf, &r);
	if(n == 0)
		return;
	/* if(!isdbgkey(r)) */ 
		qproduce(q, buf, n);
}

void
consinit(void)
{
	kbdq = qopen(512, 0, 0, 0);
	if(kbdq == 0)
		panic("no memory");
	lineq = qopen(512, 0, 0, 0);
	if(lineq == 0)
		panic("no memory");
	gkbdq = qopen(512, 0, 0, 0);
	if(gkbdq == 0)
		panic("no memory");
	randominit();
}

/*
 *  return true if current user is eve
 */
int
iseve(void)
{
	return strcmp(eve, up->env->user) == 0;
}

Chan*
consattach(char *spec)
{
	static int kp;

	if (kp == 0 && !dflag) {
		kproc("kbd", kbdslave, 0, 0);
		kp = 1;
	}
	return devattach('c', spec);
}

static Walkqid*
conswalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, contab, nelem(contab), devgen);
}

int
consstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, contab, nelem(contab), devgen);
}

Chan*
consopen(Chan *c, int omode)
{
	c = devopen(c, omode, contab, nelem(contab), devgen);
	switch((ulong)c->qid.path) {
	case Qconsctl:
		incref(&kbd.ctl);
		break;
	case Qpointer:
		if(incref(&kbd.ptr) != 1){
			decref(&kbd.ptr);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		break;
	case Qscancode:
		qlock(&kbd.gq);
		if(gkscanq || !gkscanid) {
			qunlock(&kbd.q);
			c->flag &= ~COPEN;
			if(gkscanq)
				error(Einuse);
			else
				error(Ebadarg);
		}
		gkscanq = qopen(256, 0, nil, nil);
		qunlock(&kbd.gq);
		break;
	case Qkprint:
		wlock(&kprintq.l);
		if(kprintq.q != nil){
			wunlock(&kprintq.l);
			c->flag &= ~COPEN;
			error(Einuse);
		}
		kprintq.q = qopen(32*1024, 0, 0, 0);
		if(kprintq.q == nil){
			wunlock(&kprintq.l);
			c->flag &= ~COPEN;
			error(Enomem);
		}
		qnoblock(kprintq.q, 1);
		wunlock(&kprintq.l);
		break;
	case Qsnarf:
		if(omode == ORDWR)
			error(Eperm);
		if(omode == OREAD)
			c->aux = strdup("");
		else
			c->aux = mallocz(SnarfSize, 1);
		break;
	}
	return c;
}

void
consclose(Chan *c)
{
	if((c->flag & COPEN) == 0)
		return;

	switch((ulong)c->qid.path) {
	case Qconsctl:
		if(decref(&kbd.ctl) == 0)
			kbd.raw = 0;
		break;
	case Qpointer:
		decref(&kbd.ptr);
		break;
	case Qscancode:
		qlock(&kbd.gq);
		if(gkscanq) {
			qfree(gkscanq);
			gkscanq = 0;
		}
		qunlock(&kbd.gq);
		break;
	case Qkprint:
		wlock(&kprintq.l);
		qfree(kprintq.q);
		kprintq.q = nil;
		wunlock(&kprintq.l);
		break;
	case Qsnarf:
		if(c->mode == OWRITE)
			clipwrite(c->aux, strlen(c->aux));
		free(c->aux);
		break;
	}
}

long
consread(Chan *c, void *va, long count, vlong offset)
{
	int i, n, ch, eol;
	Pointer m;
	char *p, buf[64];

	if(c->qid.type & QTDIR)
		return devdirread(c, va, count, contab, nelem(contab), devgen);

	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qsysctl:
		return readstr(offset, va, count, VERSION);
	case Qsysname:
		if(ossysname == nil)
			return 0;
		return readstr(offset, va, count, ossysname);
	case Qrandom:
		return randomread(va, count);
	case Qnotquiterandom:
		pseudoRandomBytes(va, count);
		return count;
	case Qpin:
		p = "pin set";
		if(up->env->pgrp->pin == Nopin)
			p = "no pin";
		return readstr(offset, va, count, p);
	case Qhostowner:
		return readstr(offset, va, count, eve);
	case Qhoststdin:
		return read(0, va, count);	/* should be pread */
	case Quser:
		return readstr(offset, va, count, up->env->user);
	case Qjit:
		snprint(buf, sizeof(buf), "%d", cflag);
		return readstr(offset, va, count, buf);
	case Qtime:
		snprint(buf, sizeof(buf), "%.lld", timeoffset + osusectime());
		return readstr(offset, va, count, buf);
	case Qdrivers:
		p = malloc(READSTR);
		if(p == nil)
			error(Enomem);
		n = 0;
		for(i = 0; devtab[i] != nil; i++)
			n += snprint(p+n, READSTR-n, "#%C %s\n", devtab[i]->dc,  devtab[i]->name);
		n = readstr(offset, va, count, p);
		free(p);
		return n;
	case Qmemory:
		return poolread(va, count, offset);

	case Qnull:
		return 0;
	case Qmsec:
		return readnum(offset, va, count, osmillisec(), NUMSIZE);
	case Qcons:
		qlock(&kbd.q);
		if(waserror()){
			qunlock(&kbd.q);
			nexterror();
		}

		if(dflag)
			error(Enonexist);

		while(!qcanread(lineq)) {
			qread(kbdq, &kbd.line[kbd.x], 1);
			ch = kbd.line[kbd.x];
			if(kbd.raw){
				qiwrite(lineq, &kbd.line[kbd.x], 1);
				continue;
			}
			eol = 0;
			switch(ch) {
			case '\b':
				if(kbd.x)
					kbd.x--;
				break;
			case 0x15:
				kbd.x = 0;
				break;
			case '\n':
			case 0x04:
				eol = 1;
			default:
				kbd.line[kbd.x++] = ch;
				break;
			}
			if(kbd.x == sizeof(kbd.line) || eol){
				if(ch == 0x04)
					kbd.x--;
				qwrite(lineq, kbd.line, kbd.x);
				kbd.x = 0;
			}
		}
		n = qread(lineq, va, count);
		qunlock(&kbd.q);
		poperror();
		return n;
	case Qscancode:
		if(offset == 0)
			return readstr(0, va, count, gkscanid);
		else
			return qread(gkscanq, va, count);
	case Qkeyboard:
		return qread(gkbdq, va, count);
	case Qpointer:
		m = mouseconsume();
		n = sprint(buf, "m%11d %11d %11d %11lud ", m.x, m.y, m.b, m.msec);
		if (count < n)
			n = count;
		memmove(va, buf, n);
		return n;
	case Qkprint:
		rlock(&kprintq.l);
		if(waserror()){
			runlock(&kprintq.l);
			nexterror();
		}
		n = qread(kprintq.q, va, count);
		poperror();
		runlock(&kprintq.l);
		return n;
	case Qsnarf: 
		if(offset == 0) {
			free(c->aux);
			c->aux = clipread();
		}
		if(c->aux == nil)
			return 0;
		return readstr(offset, va, count, c->aux);
	}
}

long
conswrite(Chan *c, void *va, long count, vlong offset)
{
	char buf[128], *p;
	int x, y;

	USED(offset);

	if(c->qid.type & QTDIR)
		error(Eperm);

	switch((ulong)c->qid.path) {
	default:
		error(Egreg);
	case Qcons:
		if(canrlock(&kprintq.l)){
			if(kprintq.q != nil){
				if(waserror()){
					runlock(&kprintq.l);
					nexterror();
				}
				qwrite(kprintq.q, va, count);
				poperror();
				runlock(&kprintq.l);
				return count;
			}
			runlock(&kprintq.l);
		}
		return write(1, va, count);
	case Qsysctl:
		return sysconwrite(va, count);
	case Qconsctl:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = 0;
		if(strncmp(buf, "rawon", 5) == 0) {
			kbd.raw = 1;
			return count;
		}
		else
		if(strncmp(buf, "rawoff", 6) == 0) {
			kbd.raw = 0;
			return count;
		}
		error(Ebadctl);
	case Qkeyboard:
		for(x=0; x<count; ) {
			Rune r;
			x += chartorune(&r, &((char*)va)[x]);
			gkbdputc(gkbdq, r);
		}
		return count;
	case Qpointer:
		if(count > sizeof buf-1)
			count = sizeof buf -1;
		memmove(buf, va, count);
		buf[count] = 0;
		p = nil;
		x = strtoul(buf+1, &p, 0);
		if(p == nil || p == buf+1)
			error(Eshort);
		y = strtoul(p, 0, 0);
		setpointer(x, y);
		return count;
	case Qnull:
		return count;
	case Qpin:
		if(up->env->pgrp->pin != Nopin)
			error("pin already set");
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		up->env->pgrp->pin = atoi(buf);
		return count;
	case Qtime:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		timeoffset = strtoll(buf, 0, 0)-osusectime();
		return count;
	case Quser:
		if(count >= sizeof(buf))
			error(Ebadarg);
		strncpy(buf, va, count);
		buf[count] = '\0';
		if(count > 0 && buf[count-1] == '\n')
			buf[--count] = '\0';
		if(count == 0)
			error(Ebadarg);
		if(strcmp(up->env->user, eve) != 0)
			error(Eperm);
		setid(buf, 0);
		return count;
	case Qhostowner:
		if(count >= sizeof(buf))
			error(Ebadarg);
		strncpy(buf, va, count);
		buf[count] = '\0';
		if(count > 0 && buf[count-1] == '\n')
			buf[--count] = '\0';
		if(count == 0)
			error(Ebadarg);
		if(strcmp(up->env->user, eve) != 0)
			error(Eperm);
		kstrdup(&eve, buf);
		return count;
	case Qhoststdout:
		return write(1, va, count);
	case Qhoststderr:
		return write(2, va, count);
	case Qjit:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		x = atoi(buf);
		if (x < 0 || x > 9)
			error(Ebadarg);
		cflag = x;
		return count;
	case Qsysname:
		if(count >= sizeof(buf))
			count = sizeof(buf)-1;
		strncpy(buf, va, count);
		buf[count] = '\0';
		kstrdup(&ossysname, buf);
		return count;
	case Qsnarf:
		if(offset+count >= SnarfSize)
			error(Etoobig);
		snarftab->qid.vers++;
		memmove((uchar*)(c->aux)+offset, va, count);
		return count;
	}
	return 0;
}

static int	
sysconwrite(void *va, ulong count)
{
	Cmdbuf *cb;
	int e;
	cb = parsecmd(va, count);
	if(waserror()){
		free(cb);
		nexterror();
	}
	if(cb->nf == 0)
		error(Enoctl);
	if(strcmp(cb->f[0], "reboot") == 0){
		osreboot(rebootargv[0], rebootargv);
		error("reboot not supported");
	}else if(strcmp(cb->f[0], "halt") == 0){
		if(cb->nf > 1)
			e = atoi(cb->f[1]);
		else
			e = 0;
		cleanexit(e);		/* XXX ignored for the time being (and should be a string anyway) */
	}else if(strcmp(cb->f[0], "broken") == 0)
		keepbroken = 1;
	else if(strcmp(cb->f[0], "nobroken") == 0)
		keepbroken = 0;
	else if(strcmp(cb->f[0], "exdebug") == 0)
		exdebug = !exdebug;
	else
		error(Enoctl);
	poperror();
	free(cb);
	return count;
} 

Dev consdevtab = {
	'c',
	"cons",

	consinit,
	consattach,
	conswalk,
	consstat,
	consopen,
	devcreate,
	consclose,
	consread,
	devbread,
	conswrite,
	devbwrite,
	devremove,
	devwstat
};

/*
 * the following will move to devpointer.c
 */

typedef struct Ptrevent Ptrevent;

struct Ptrevent {
	int	x;
	int	y;
	int	b;
	ulong	msec;
};

enum {
	Nevent = 16	/* enough for some */
};

static struct {
	Lock	lk;
	int	rd;
	int	wr;
	Ptrevent	clicks[Nevent];
	Rendez r;
	int	full;
	int	put;
	int	get;
} ptrq;

static Pointer mouse = {-32768,-32768,0};

void
mouseproduce(Pointer m)
{
	int lastb;
	Ptrevent e;

	lock(&ptrq.lk);
	e.x = m.x;
	e.y = m.y;
	e.b = m.b;
	e.msec = osmillisec();
	lastb = mouse.b;
	mouse.x = m.x;
	mouse.y = m.y;
	mouse.b = m.b;
	mouse.msec = e.msec;
	if(!ptrq.full && lastb != m.b){
		ptrq.clicks[ptrq.wr] = e;
		if(++ptrq.wr == Nevent)
			ptrq.wr = 0;
		if(ptrq.wr == ptrq.rd)
			ptrq.full = 1;
	}
	mouse.modify = 1;
	ptrq.put++;
	unlock(&ptrq.lk);
	Wakeup(&ptrq.r);
/*	drawactive(1); */
}

static int
ptrqnotempty(void *a)
{
	USED(a);
	return ptrq.full || ptrq.put != ptrq.get;
}

Pointer
mouseconsume(void)
{
	Pointer m;
	Ptrevent e;

	Sleep(&ptrq.r, ptrqnotempty, 0);
	lock(&ptrq.lk);
	ptrq.full = 0;
	ptrq.get++;
	if(ptrq.rd != ptrq.wr){
		e = ptrq.clicks[ptrq.rd];
		if(++ptrq.rd >= Nevent)
			ptrq.rd = 0;
		memset(&m, 0, sizeof(m));
		m.x = e.x;
		m.y = e.y;
		m.b = e.b;
		m.msec = e.msec;
	}else
		m = mouse;
	unlock(&ptrq.lk);
	return m;
}
