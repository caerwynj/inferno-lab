#include <linux/fb.h>
#include <linux/input.h>

/* touchscreen/keys specific handheld functions */
typedef struct Tscreen Tscreen;
struct Tscreen {
	char *scrdev;
	char *keydev;
	int scrfd;
	int keyfd;
	int b;

	int (*config)(void);
	void (*stylus)(struct input_event *, int);
	void (*keys)(struct input_event *, int);
};

extern struct Tscreen ts;
extern int ispointervisible;

