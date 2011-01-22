#include <lib9.h>
#include <isa.h>
#include <interp.h>
#include "runt.h"
#include "raise.h"
#include "vxrunmod.h"
#include "kernel.h"
#include "vx32.h"

/* 
 * Some of the code in this file is taken from vx32/src/vxrun/vxrun.c
 */
 
#define V (void*)(uintptr_t)

#define RET proc->cpu->reg[EAX]
#define NUM proc->cpu->reg[EAX]
#define ARG1 proc->cpu->reg[EDX]
#define ARG2 proc->cpu->reg[ECX]
#define ARG3 proc->cpu->reg[EBX]
#define ARG4 proc->cpu->reg[EDI]
#define ARG5 proc->cpu->reg[ESI]

extern char **environ;
int trace = 1;

enum
{
	VXSYSEXIT = 1,
	VXSYSBRK = 2,
	VXSYSREAD = 3,
	VXSYSWRITE = 4,
	VXSYSOPEN = 5,
	VXSYSCLOSE = 6,
	VXSYSLSEEK = 7,
	VXSYSREMOVE = 8,
	VXSYSTIME = 9,	// gettimeofday
	VXSYSCLOCK = 10,
	VXSYSSTAT = 11,
	VXSYSFSTAT = 12,
	VXSYSGETCWD = 13,
	VXSYSCHDIR = 14,
	VXSYSCHMOD = 15,
	VXSYSDUP = 16,
	VXSYSLINK = 17,
	VXSYSSELECT = 18,
	VXSYSMKDIR = 19,
	VXSYSFCNTL = 20,
	VXSYSTRUNCATE = 21,
	VXSYSFTRUNCATE = 22,
	VXSYSLSTAT = 23,
	VXSYSFORK = 24,
	VXSYSWAITPID = 25,
	VXSYSEXEC = 26,
	VXSYSPIPE = 27,
	VXSYSSLEEP = 28,
	VXSYSGETPID = 29,
};

static void 
dumpregs(struct vxproc *p)
{
	struct vxcpu *c = p->cpu;

	print("eax %08x  ecx %08x  edx %08x  ebx %08x\n",
		c->reg[EAX], c->reg[ECX], c->reg[EDX], c->reg[EBX]);
	print("esp %08x  ebp %08x  esi %08x  edi %08x\n",
		c->reg[ESP], c->reg[EBP], c->reg[ESI], c->reg[EDI]);
	print("eip %08x  eflags %08x\n",
		c->eip, c->eflags);
}

static int 
dosyscall(vxproc *proc, int* fret)
{
	int fd, p[2], *vp, ret, mode, umode;
	uint32_t addr, saddr, oaddr;
	int len;
	vxmmap *m;
	struct stat st;
	uint32_t inc;
	uint32_t secs;
	
	m = vxmem_map(proc->mem, 0);

	switch (NUM) {
	case VXSYSEXIT:
		*fret = ARG1;
/*		if (ARG1 != 0)
			exit(ARG1);
*/
		return 0;
		break;
	case VXSYSBRK:
		addr = ARG1;
		inc = 1<<20;
		addr = (addr + inc - 1) & ~(inc - 1);
		oaddr = m->size;
		if (addr == oaddr) {
			ret = 0;
			break;
		}
		ret = 0;
		if (addr > m->size)
			ret = vxmem_resize(proc->mem, addr);
		if (trace)
			print("sbrk %p -> %p / %p; %d\n", V oaddr, V addr, V ARG1, ret);
		if (ret < 0)
			print("warning: sbrk failed. caller will be unhappy!\n");
		if (ret >= 0) {
			if (addr > oaddr)
				ret = vxmem_setperm(proc->mem, oaddr, addr - oaddr, VXPERM_READ|VXPERM_WRITE);
			if(ret < 0)
				print("setperm is failing! %p + %p > %p ? \n", V oaddr, V(addr - oaddr), V m->size);
		}
		break;
	case VXSYSREAD:
		fd = ARG1;
		addr = ARG2;
		len = ARG3;
		if (!vxmem_checkperm(proc->mem, addr, len, VXPERM_WRITE, NULL))
			print("bad arguments to read");
		ret = kread(fd, (char*)m->base + addr, len);
		break;
	case VXSYSWRITE:
		fd = ARG1;
		addr = ARG2;
		len = ARG3;
		if (!vxmem_checkperm(proc->mem, addr, len, VXPERM_READ, NULL))
			print("bad arguments to write");
		ret = kwrite(fd, (char*)m->base + addr, len);
		break;
	case VXSYSOPEN:
		addr = ARG1;
		mode = ARG2;
		umode = mode&3;
		/*
		if(mode & VXC_O_CREAT)
			umode |= O_CREAT;
		if(mode & VXC_O_EXCL)
			umode |= O_EXCL;
		if(mode & VXC_O_NOCTTY)
			umode |= O_NOCTTY;
		if(mode & VXC_O_TRUNC)
			umode |= O_TRUNC;
		if(mode & VXC_O_APPEND)
			umode |= O_APPEND;
		if(mode & VXC_O_NONBLOCK)
			umode |= O_NONBLOCK;
		if(mode & VXC_O_SYNC)
			umode |= O_SYNC;
		if (!checkstring(proc->mem, m->base, addr))
			goto einval;
		*/
		ret = kopen((char*)m->base+addr, umode);
		print("open %s %#x %#o => %d\n", (char*)m->base+addr, ARG2, ARG3, ret);
		break;
	case VXSYSCLOSE:
		fd = ARG1;
		if (fd < 0){
		/* TODO 
			goto einval;
		*/	
		}
		ret = kclose(fd);
		break;
	default:
		dumpregs(proc);
		print("vxrun: bad system call %d\n", NUM);
	}
	RET = ret;
	return 1;
}

void
vxrunmodinit(void)
{
	builtinmod("$Vxrun", Vxrunmodtab, Vxrunmodlen);
}

void
Vxrun_run(void *fp)
{
	List *l;
	F_Vxrun_run *f;
	int ret = 0;
	int n = 0;
	char* argv0;
	char*argv[32];
	
	f = fp;
	for(l = f->args, n = 0; l != H; l = l->tail){
		argv[n] = string2c(*l->data);
		n++;
	}
	argv[n] = 0;
	argv0 = string2c(*f->args->data);
	release();
	print("nargs %d, argv0 %s\n", n, argv0);
	ret = vx32_siginit();
	if(ret < 0){
		print("vxrun: failed vx32_siginit()\n");
		*f->ret = -1;
		acquire();
		return;
	}
	print("vxrun hello\n");
	vxproc *volatile p = vxproc_alloc();
	if (p == NULL){
		*f->ret = -2;
		acquire();
		return;
	}
	print("vxrun load file\n");
	if (vxproc_loadelffile(p, 
			argv0, 
			argv,
			0) < 0){
		*f->ret = -3;
		print("vxrun vxproc_loadelffile failed\n");
		acquire();
		return;
	}
	print("vxrun file loaded\n");
	for (;;) {
		int rc = vxproc_run(p);
		if (rc < 0){
			acquire();
			*f->ret = -4;
			return;
		/*	fatal("vxproc_run: %s\n", strerror(errno)); */
		}
		if (rc == VXTRAP_SYSCALL) {
			if(dosyscall(p, f->ret))
				continue;
			else
				break;
		}
		dumpregs(p);
		*f->ret = -5;
		acquire();
		return;
	}
	acquire();
	return;
}
