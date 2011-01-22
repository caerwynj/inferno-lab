implement Reader;

include "sh.m";
include "sys.m";
	sys: Sys;
include "draw.m";
include "mapred.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

map: Mapper;
emit: chan of (string, string);

init(m: Mapper, e: chan of (string, string))
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	map = m;
	emit = e;
}

read(file: string, nil: big, nil: big)
{
	fd := filter("/dis/man2txt.dis" :: file :: nil);
	if(fd == nil) {
		sys->fprint(sys->fildes(2), "couldn't open filter %r\n");
		return;
	}
	io := bufio->fopen(fd, Sys->OREAD);
	while((s := io.gets('\n')) != nil){
		map->map(file, s, emit);
	}
}

exec(sync: chan of int, cmd : string, argl : list of string, out: array of ref Sys->FD)
{
	file := cmd;
	if(len file<4 || file[len file-4:]!=".dis")
		file += ".dis";

	sys->pctl(Sys->FORKFD, nil);
	sys->dup(out[1].fd, 1);
	out[0] = nil;
	out[1] = nil;
	sync <-= sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);
	c := load Command file;
	if(c == nil) {
		err := sys->sprint("%r");
		if(file[0]!='/' && file[0:2]!="./"){
			c = load Command "/dis/"+file;
			if(c == nil)
				err = sys->sprint("%r");
		}
		if(c == nil){
			# debug(sys->sprint("file %s not found\n", file));
			sys->fprint(sys->fildes(2), "%s: %s\n", cmd, err);
			return;
		}
	}
	c->init(nil, argl);
}

filter(argl: list of string): ref Sys->FD
{
	p := array[2] of ref Sys->FD;

	if(sys->pipe(p) < 0)
		return nil;
	sync := chan of int;
	spawn exec(sync, hd argl, argl, (array[2] of ref Sys->FD)[0:] = p);
	<-sync;
	p[1] = nil;
	return p[0];
}
