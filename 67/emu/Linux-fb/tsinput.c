#include "dat.h"
#include "fns.h"
#include "tsinput.h"

enum
{
	NEVENTS = 5,
	EVENTSZ = sizeof(struct input_event),
};

static void 
tsProc(void* dummy)
{
	int count;
	struct input_event ev[NEVENTS];
	for(;;) {
		count = read(ts.scrfd, ev, sizeof(ev));
		if(count >= EVENTSZ)
			ts.stylus(ev, count / EVENTSZ);
	}
}

static void 
keysProc(void* dummy)
{
	int count;
	struct input_event ev[NEVENTS];
	for(;;) {
		count = read(ts.keyfd, ev, sizeof(ev));
		if(count >= EVENTSZ)
			ts.keys(ev, count / EVENTSZ);
	}
}

static void 
tsinput_init(void)
{
	if (ts.config() < 0)
		return;

	if(kproc("tsProc", tsProc, nil, 0) < 0) {
		fprint(2, "emu: can't start touchscreen procedure");
		close(ts.scrfd);
		close(ts.keyfd);
		return;
	}

	if(kproc("keysProc", keysProc, nil, 0) < 0) {
		fprint(2, "emu: can't start keys procedure");
		close(ts.scrfd);
		close(ts.keyfd);
		return;
	}

}

void 
tsinputlink()
{
	ispointervisible = 1; // have pointer only under acme?
	tsinput_init();
}

