implement PAPER;

include "sys.m";
include "paper.m";
	sys:	Sys;
include "daytime.m";
	daytime: Daytime;

Stree: adt {
	name:	string;
	date:	int;
	sl:	int;
	sr:	int;
};
NST:	con 40;
tree:	array of ref Stree;
ntree:	int;
date:	int;
dir	:= "/services/news/lnw/";

scanpaper(loc: string): (string, string, list of ref Article)
{
	if (sys==nil)
		sys = load Sys Sys->PATH;
	if (daytime==nil) {
		daytime = load Daytime Daytime->PATH;
		if(daytime == nil)
			return ("Today", "No daytime module", nil);
	}

	(nil, lloc) := sys->tokenize(loc, "/");
	while (len lloc > 1)
		lloc = tl lloc;
	fd := sys->open(dir, Sys->OREAD);
	if (fd==nil)
		return ("", sys->sprint("Can't open LNW directory: %r\n"), nil);
	for (;;) {
		i: int;
		(n, stf) := sys->dirread(fd);
		if (n<=0)
			break;
		for (i=0; i<n; i++)
			newstory(stf[i]);
	}
	l := sendstories(0, nil);	# list of NST most recent, in reverse order
	l1: list of ref Article = nil;
	nstory := len l;
	nseen := 0;
	for (; l!=nil; l=tl l) {
		nseen++;
		if (nseen >= nstory-NST) {
			st := title(hd l);
			if (st.title!=nil)
				l1 = st :: l1;
		}
	}
	if (len l1 == 0)
		return ("Today", "Sorry, no LNW articles found\n", nil);
	tm := daytime->local(date);
	return (daytime->text(tm), "", l1);
}

sendstories(tp: int, l: list of ref Article): list of ref Article
{
	if (tree[tp].sl != 0)
		l = sendstories(tree[tp].sl, l);
	l = ref Article(nil, tree[tp].name, "") :: l;
	if (tree[tp].sr != 0)
		l = sendstories(tree[tp].sr, l);
	return l;
}

title(s: ref Article): ref Article
{
	fd := sys->open(dir+s.bodynm, sys->OREAD);
	if (fd == nil) {
		s.title = sys->sprint("<Can't open %s>", dir+s.bodynm);
		return s;
	}
	h := array[128] of byte;
	if (sys->read(fd, h, 128) <= 0)
		return s;
	(nl, l) := sys->tokenize(string h, "\n");
	if (nl<2)
		return s;
	slug := hd tl l;
	if (len slug < 5)
		return s;
	(nl, l) = sys->tokenize(slug[5:len slug], ",");
	if (nl<=0)
		return s;
	s.title = hd l;
	return s;
}

getarticle(s: string): string
{
	f := sys->open(dir+s, sys->OREAD);
	if (f==nil)
		return nil;
	buf := array[10000] of byte;
	n := sys->read(f, buf, 10000);
	if (n <= 0)
		return nil;
	art: list of string;
	(n, art) = sys->tokenize(string buf[0:n], "\n");
	if (n >= 2) {
		art = tl tl art;
		n -= 2;
	}
	ap := art;
	as: string;
	for (; ap!=nil; ap = tl ap) {
		if ((hd ap)[0] == '\t' || (hd ap)[0]=='^') {
			as += "\n\n  ";
			as += (hd ap)[1:len hd ap];
		} else
			as += " " + hd ap;
	}
	return as;
}

newstory(sd: Sys->Dir)
{
	tp := 0;
	np: ref Stree;

	if ((sd.name[0]!='a' && sd.name[0]!='b' && sd.name[0]!='f')
	  || len sd.name!=5 || sd.name[1]<'0' || sd.name[1]>'9')
		return;
	np = ref Stree(sd.name, sd.mtime, 0, 0);
	if (sd.mtime > date)
		date = sd.mtime;
	if (len tree==0) {
		tree = array[10] of ref Stree;
		tree[0] = np;
		ntree = 1;
		return;
	}
	if (ntree>=len tree) {
		newtree := array[(ntree + ntree/2)] of ref Stree;
		for (i := 0; i <ntree; i++)
			newtree[i] = tree[i];
		tree = newtree;
		newtree = nil;
	}
	for (;;) {
		if (np.name <= tree[tp].name) {  # in real life, use np.date >= tree[tp].date
			if (tree[tp].sl==0) {
				tree[tp].sl = ntree;
				tree[ntree] = np;
				ntree++;
				return;
			}
			tp = tree[tp].sl;
			continue;
		}
		if (np.name > tree[tp].name) {
			if (tree[tp].sr==0) {
				tree[tp].sr = ntree;
				tree[ntree] = np;
				ntree++;
				return;
			}
			tp = tree[tp].sr;
			continue;
		}
		return;
	}
}
