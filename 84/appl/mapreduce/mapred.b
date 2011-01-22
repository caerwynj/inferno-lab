implement MapReduce;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "readdir.m";
	readdir: Readdir;
include "mapred.m";
	mapper: Mapper;
	reducer: Reducer;
	reader: Reader;
include "arg.m";
	arg: Arg;

MapReduce: module {
	init:fn(nil: ref Draw->Context, args:list of string);
};


R := 13;
M := 16;
emit: chan of (string, string);

init(nil: ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	readdir = load Readdir Readdir->PATH;
	arg = load Arg Arg->PATH;
	readname := "lineread";
	
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'r' =>
			readname = arg->earg();
		}

	args =arg->argv();
	if(len args < 2)
		exit;

	mapper = load Mapper "/dis/mapreduce/" + hd args + ".dis";
	args = tl args;
	if(mapper == nil){
		warn("mapper", "");
		exit;
	}
	reducer = load Reducer "/dis/mapreduce/" + hd args + ".dis";
	if(reducer == nil){
		warn("reducer", "");
		exit;
	}
	
	reader = load Reader "/dis/mapreduce/" + readname + ".dis";
	if(reader == nil){
		warn("reader", "");
		exit;
	}
	args = tl args;

	emit = chan of (string, string);
	sync := chan of int;
	filelst : list of string;
	rlst : list of string;
	pid := sys->pctl(0, nil);
	
	reader->init(mapper, emit);
	for(i := 0; i < R; i++){
		filelst = "/tmp/mapred." + string pid + "." + string i :: filelst;
		rlst = "out." + string i :: rlst;
	}
	spawn intermediate(filelst, emit, sync);
	<-sync;
	if(args==nil)
		args = "." :: nil;
	for(; args!=nil; args = tl args)
		du(hd args);
	sync <-= 1;
	for(l := filelst; l != nil; l = tl l){
		spawn reduce(hd l, hd rlst);
		rlst = tl rlst;
	}
}


intermediate(filelst: list of string, pair: chan of (string, string), sync: chan of int)
{
	sync <-= sys->pctl(0, nil);
	fds := array[len filelst] of ref Iobuf;
	i := 0;
	for(; filelst != nil; filelst = tl filelst)
		fds[i++] = bufio->create(hd filelst, Sys->ORDWR, 8r666);

	loop: for(;;) alt {
	(k, v) := <-pair =>
		if(k == nil)
			break loop;
		h := fun1(k, len fds);
		fds[h].puts(sys->sprint("%s %s\n", k, v));
	<-sync =>
		break loop;
	}
	for(i = 0; i < len fds; i++)
		fds[i].close();
}

# from Aho Hopcroft Ullman
fun1(s:string, n:int):int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

# Avoid loops in tangled namespaces.
NCACHE: con 1024; # must be power of two
cache := array[NCACHE] of list of ref sys->Dir;

seen(dir: ref sys->Dir): int
{
	h := int dir.qid.path & (NCACHE-1);
	for(c := cache[h]; c!=nil; c = tl c){
		t := hd c;
		if(dir.qid.path==t.qid.path && dir.dtype==t.dtype && dir.dev==t.dev)
			return 1;
	}
	cache[h] = dir :: cache[h];
	return 0;
}

dir(dirname: string): big
{
	prefix := dirname+"/";
	if(dirname==".")
		prefix = nil;
	sum := big 0;
	(de, nde) := readdir->init(dirname, readdir->NAME);
	if(nde < 0)
		warn("can't read", dirname);
	for(i := 0; i < nde; i++) {
		s := prefix+de[i].name;
		if(de[i].mode & Sys->DMDIR){
			if(!seen(de[i])){	# arguably should apply to files as well
				size := dir(s);
				sum += size;
			}
		}else{
			l := de[i].length;
			sum += l;
			reader->read(s, big 0, l);
		}
	}
	return sum;
}

du(name: string)
{
	(rc, d) := sys->stat(name);
	if(rc < 0){
		warn("can't stat", name);
		return;
	}
	if(d.mode & Sys->DMDIR){
		d.length = dir(name);
		return;
	}else
		reader->read(name, big 0, d.length);
}

warn(why: string, f: string)
{
	sys->fprint(sys->fildes(2), "mapred: %s %q: %r\n", why, f);
}


Incr: con 2000;		# growth quantum for record array

reduce(file: string, tgt: string)
{
	io := bufio->open(file, Sys->OREAD);
	if(io == nil)
		return;
	out := bufio->create(tgt, Sys->OWRITE, 8r666);
	if(out == nil)
		return;
	last := "";
	values : chan of string;
	a := array[Incr] of string;
	n := 0;
	while ((s := io.gets('\n')) != nil) {
		if (n >= len a) {
			b := array[len a + Incr] of string;
			b[0:] = a;
			a = b;
		}
		a[n++] = s;
	}
	mergesort(a, array[n] of string, n);
	done := chan of int;
	for (i := 0; i < n; i++){
		(nf, f) := sys->tokenize(a[i], " \t\n\r");
		if(nf != 2)
			continue;
		if(hd f == last){
			values <-= hd tl f;
		}else{
			if(last != ""){
				values <-= nil;
				<-done;
			}
			last = hd f;
			values = chan of string;
			spawn emiter(out, last, values, done);
			values <-= hd tl f;
		}
	}
	if(last != ""){
		values <-= nil;
		<-done;
	}
	out.close();
	sys->remove(file);
}

emiter(out: ref Iobuf, key: string, input: chan of string, done: chan of int)
{
	sync := chan of int;
	output:= chan of string;
	spawn reduceworker(sync, key, input, output);
	<-sync;
	loop: for(;;) alt {
	s := <-output =>
		out.puts(sys->sprint("%s %s\n", key, s));
	<-sync =>
		break loop;
	}
	done <-= 1;
}

reduceworker(sync: chan of int, k: string, input: chan of string, output: chan of string)
{
	sync <-= sys->pctl(0, nil);
	reducer->reduce(k, input, output);
	sync <-= 1;
}

mergesort(a, b: array of string, r: int)
{
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m], m);
		mergesort(a[m:r], b[m:r], r-m);
		b[0:] = a[0:r];
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if (b[i] > b[j])
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}
