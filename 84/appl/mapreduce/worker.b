implement Worker;

include "sh.m";
include "sys.m";
	sys : Sys;
	print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "mapred.m";
	mapper: Mapper;
	reducer: Reducer;
	reader: Reader;
include "arg.m";
	arg: Arg;


Worker: module {
	init:fn(nil: ref Draw->Context, args: list of string);
};

R := 13;
emit: chan of (string, string);
modname: string;
readname: string;

Map, Reduce: con iota;
wtype: int;
id: int;
mfd: ref Sys->FD;

# open /n/client/mnt/mr/clone
# read argl from first line: type id R module.dis
init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	arg = load Arg Arg->PATH;
	
	args = tl args;
	if(len args != 1)
		exit;
	mfd = sys->open(hd args, Sys->ORDWR);
	if(mfd == nil)
		exit;
	buf := array[1024] of byte;
	n := sys->read(mfd, buf, len buf);
	if(n < 0) {
		warn("reading args %r\n", "");
		exit;
	}
	(nil, args) = sys->tokenize(string buf[:n], " \t\r\n");
	readname = "lineread";
	arg->init(args);
	id = 0;
	while((c := arg->opt()) != 0)
		case c {
			'm' =>
				wtype = Map;
			'r' =>
				wtype = Reduce;
			'R' =>
				R = int arg->earg();
			'd' =>
				modname = arg->earg();
			'i' =>
				id = int arg->earg();
		}

	args = arg->argv();
	
	if(wtype == Map)
		domap();
	else
		doreduce();
}

domap()
{
	mapper = load Mapper "/dis/mapreduce/" +modname + ".dis";
	if(mapper == nil){
		warn("mapper", "");
		exit;
	}
	reader = load Reader "/dis/mapreduce/" + readname + ".dis";
	if(reader == nil){
		warn("reader", "");
		exit;
	}
	buf := array[1024] of byte;
	emit = chan of (string, string);
	sync := chan of int;
	filelst : list of string;
	
	reader->init(mapper, emit);
	for(i := 0; i < R; i++){
		filelst = "/tmp/mapred." + string id + "." + string i :: filelst;
	}
	spawn intermediate(filelst, emit, sync);
	<-sync;
	while((n := sys->read(mfd, buf, len buf)) > 0){
		(nf, flds) := sys->tokenize(string buf[:n], " \t\n");
		if(nf != 3)
			continue;
		reader->read(hd flds, big hd tl flds, big hd tl tl flds);
	}
	sync <-= 1;
}

doreduce()
{
	reducer = load Reducer "/dis/mapreduce/" + modname + ".dis";
	if(reducer == nil){
		warn("reducer", "");
		exit;
	}
	buf := array[1024] of byte;
	
	pin := array[2] of ref Sys->FD;
	if(sys->pipe(pin) < 0){
		warn("creating pipe", "");
		return;
	}
	pout := array[2] of ref Sys->FD;
	if(sys->pipe(pout) < 0){
		warn("creating pipe", "");
		return;
	}
	sync := chan of int;
	spawn sort(sync, (array[2] of ref Sys->FD)[0:] = pin, (array[2] of ref Sys->FD)[0:] = pout);
	<-sync;
	pin[1] = nil;
	pout[1] = nil;
	while((n := sys->read(mfd, buf, len buf)) > 0){
		(nf, flds) := sys->tokenize(string buf[:n], " \t\n");
		if(nf != 3)
			continue;
		gather(hd flds, pin[0]);
	}
	pin[0] = nil;
	reduce("/tmp/out." + string id, pout[0]);
}

sort(sync: chan of int, ifds: array of ref Sys->FD, ofds: array of ref Sys->FD)
{
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(ifds[1].fd, 0);
	sys->dup(ofds[1].fd, 1);
	ifds[0] = nil;
	ifds[1] = nil;
	ofds[0] = nil;
	ofds[1] = nil;
	sync <-= sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);
	c := load Command "/dis/mapreduce/sort.dis";
	c->init(nil, "sort" :: nil);
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


gather(file: string, stdout: ref Sys->FD)
{
	n: int;
	fd: ref Sys->FD;
	buf := array[8192] of byte;

	fd = sys->open(file, sys->OREAD);
	if(fd == nil) {
		warn("cannot open", file);
		exit;
	}
	for(;;) {
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;
		if(sys->write(stdout, buf, n) < n) {
			warn("write error", "");
			exit;
		}
	}
	if(n < 0) {
		warn("read error", "");
		exit;
	}
}

reduce(tgt: string, in : ref Sys->FD)
{
	out := bufio->create(tgt, Sys->OWRITE, 8r666);
	if(out == nil)
		return;
	io := bufio->fopen(in, Bufio->OREAD);
	last := "";
	values : chan of string;
	done := chan of int;
	while((s := io.gets('\n')) != nil){
		(nf, f) := sys->tokenize(s, " \t\n\r");
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

warn(why: string, f: string)
{
	sys->fprint(sys->fildes(2), "worker: %s %q: %r\n", why, f);
}
