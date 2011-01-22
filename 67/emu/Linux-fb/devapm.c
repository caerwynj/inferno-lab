#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

#include	<unistd.h>
#include	<linux/apm_bios.h>
#include	<linux/fb.h>


enum{
	Qdir,
	Qapm,
};

static
Dirtab apmtab[]={
	".",		{Qdir, 0, QTDIR},	0,	0555,	/* entry for "." must be first if devgen used */
	"apm",		{Qapm, 0},	0,	0666,
};


static Lock apmlock;
static int  apmfd = -1;
static Lock proclock;
static int  procfd = -1;

int apm_dev_init()
{
	int result;
	lock(&apmlock);
	result = ((apmfd == -1) && ((apmfd = open("/dev/apm_bios", O_WRONLY)) < 0)) ? 1 : 0;
	unlock(&apmlock);
	return result;
}

int apm_proc_init()
{
	int result;
	lock(&proclock);
	result = ((procfd == -1) && ((procfd = open("/proc/apm", O_RDONLY))< 0)) ? 1 : 0;
	unlock(&proclock);
	return result;
}

int apm_dev_close()
{
	int result;
	lock(&apmlock);
	result = ((apmfd == -1) || close(apmfd)) ? 1 : 0;
	apmfd = -1;
	unlock(&apmlock);
	return result;
}

int apm_proc_close()
{
	int result;
	lock(&proclock);
	result = ((procfd == -1) || close(procfd)) ? 1 : 0;
	procfd = -1;
	unlock(&proclock);
	return result;
}


void apm_suspend()
{
	int result;
	if(apm_dev_init())
		return;
	sync();
	lock(&apmlock);
	result = ioctl(apmfd, APM_IOC_SUSPEND, 0);
	unlock(&apmlock);
	if(result)
		error(Eio);
}

int apm_blank(int vesastt)
{
	int fbfd, result;
	static int currvesastt = -1;

	if (currvesastt == vesastt)
		return 0;	
	if ((fbfd = open("/dev/fb0", O_RDWR)) < 0)
		return -1;

	lock(&apmlock);
	result = ioctl(fbfd, FBIOBLANK, vesastt);
	unlock(&apmlock);
	close(fbfd);
	if(result)
		error(Eio);
	else
		currvesastt = vesastt;
	return result;
}

static Chan*
apmattach(char* spec)
{
	if(apm_dev_init() || apm_proc_init())
		error(Enoattach);
	return devattach('S', spec);
}

static Walkqid*
apmwalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, apmtab, nelem(apmtab), devgen);
}

static int
apmstat(Chan* c, uchar *db, int n)
{
	return devstat(c, db, n, apmtab, nelem(apmtab), devgen);
}

static Chan*
apmopen(Chan* c, int omode)
{
	apm_proc_init();
	return devopen(c, omode, apmtab, nelem(apmtab), devgen);  
}

static void
apmclose(Chan* c)
{
	USED(c);
	apm_proc_close();
}

static long
apmread(Chan* c, void* a, long n, vlong offset)
{
	USED(offset);
	switch((ulong)c->qid.path) {
	case Qdir:
		return devdirread(c, a, n, apmtab, nelem(apmtab), devgen);
	case Qapm: {
		char buffer[100] = {0};
		char driver_version[10] = {0};
		int version_major = 0;
		int version_minor = 0;
		int flags = 0;
		int line_status = 0;
		int battery_status = 0;
		int battery_flags = 0;
		int battery_percentage = 0;
		int battery_time = 0;
		char units[10] = {0};
		if(read(procfd, buffer, sizeof(buffer)) < 0)
			error(Eio);
		sscanf(buffer, "%s %d.%d %x %x %x %x %d%% %d %s\n",
		       driver_version,
		       &version_major,
		       &version_minor,
		       &flags,
		       &line_status,
		       &battery_status,
		       &battery_flags,
		       &battery_percentage,
		       &battery_time,
		       units);
		int result = sprint(buffer, "%s %d%% %d min ", 
				    ((battery_status) ? "online" : "offline"),
				    (((battery_percentage >= 0) && (battery_percentage <= 100)) ? battery_percentage : 0),
				    (strncmp(units, "min", sizeof("min")) ? (battery_time / 60) : battery_time));
		return readstr(offset, a, n, buffer);
	}
	default:
		n=0;
		break;
	}
	return n;
}


static long
apmwrite(Chan* c, void* a, long n, vlong offset)
{
	char buffer[128] = {0};
	USED(a);
	USED(offset);
	switch((ulong)c->qid.path) {
	case Qapm:
		if(n > sizeof(buffer))
			n = sizeof(buffer)- 1;
		strncpy(buffer, a, n);
		if(strncmp(buffer, "suspend", sizeof("suspend")) == 0) {
			apm_suspend();
			return n;
		}else if(strncmp(buffer, "blank", sizeof("blank")) == 0) {
			apm_blank(VESA_POWERDOWN);
			return n;
		}
		error(Ebadctl);
		break;
	default:
		error(Ebadusefd);
	}
	return n;
}

Dev apmdevtab = {					/* defaults in dev.c */
	'S',
	"apm",

	devinit,					/* devinit */
	apmattach,
	apmwalk,
	apmstat,
	apmopen,
	devcreate,					/* devcreate */
	apmclose,
	apmread,
	devbread,					/* devbread */
	apmwrite,
	devbwrite,					/* devbwrite */
	devremove,					/* devremove */
	devwstat,					/* devwstat */
};
