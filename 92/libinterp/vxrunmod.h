typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;
Runtab Vxrunmodtab[]={
	"run",0x9c11df7a,Vxrun_run,40,2,{0x0,0x80,},
	0
};
#define Vxrunmodlen	1
