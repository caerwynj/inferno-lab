implement Chunkqueue;
include "sys.m";
	sys: Sys;
include "draw.m";
include "string.m";
	str: String;
include "rand.m";
	rand: Rand;

stderr: ref Sys->FD;

Chunkqueue: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	rand = load Rand Rand->PATH;
	rand->init(0);
	str = load String String->PATH;
	stderr = sys->fildes(2);
	if (len argv < 2 || len argv > 3) {
		sys->fprint(stderr, "usage: ramfile path [data]\n");
		return;
	}
	path := hd tl argv;
	(dir, f) := pathsplit(path);

	if (sys->bind("#s", dir, Sys->MBEFORE|Sys->MCREATE) == -1) {
		sys->fprint(stderr, "chunkqueue: %r\n");
		return;
	}
	fio := sys->file2chan(dir, f);
	if (fio == nil) {
		sys->fprint(stderr, "chunkqueue: file2chan failed: %r\n");
		return;
	}
	spawn server(fio);
}

HostQ: adt {
	host: string;
	clist: list of string;
};

hostl : list of ref HostQ;

lookup(host: string): ref HostQ
{
	for(l := hostl; l != nil; l = tl l){
		if((hd l).host == host)
			return hd l;
	}
	return nil;
}


server(fio: ref Sys->FileIO)
{
	for (;;) alt {
	(nil, nil, nil, rc) := <-fio.read =>
		if (rc != nil) {
			if (len hostl == 0)
				rc <-= (nil, nil);
			else {
				s := nextdisk();
				if(s == nil)
					rc <-= (nil, nil);
				else
					rc <-= (array of byte s, nil);
			}
		}
	(nil, d, nil, wc) := <-fio.write =>
		if (wc != nil){
			(chunk, host) := str->splitl(string d, " ");
			host = host[1:];
			h := lookup(host);
			if(h != nil){
				for(l := h.clist; l != nil; l = tl l)
					if((hd l) == chunk)
						break;
				if(l == nil)
					h.clist = chunk :: h.clist;
			}else{
				hostl = ref HostQ(host, chunk :: nil) :: hostl;
			}
			wc <-= (len d, nil);
		}
	}
}

pathsplit(p: string): (string, string)
{
	for (i := len p - 1; i >= 0; i--)
		if (p[i] != '/')
			break;
	if (i < 0)
		return (p, nil);
	p = p[0:i+1];
	for (i = len p - 1; i >=0; i--)
		if (p[i] == '/')
			break;
	if (i < 0)
		return (".", p);
	return (p[0:i+1], p[i+1:]);
}

nextdisk(): string
{
	while(len hostl > 0){
		n := rand->rand(len hostl);
		sl := hostl;
		save : list of ref HostQ;
		for(i := 0; i<n; i++){
			save = hd sl :: save;
			sl = tl sl;
		}
		for( ; sl != nil; sl = tl sl){
			h := hd sl;
			if(h.clist != nil) {
				chunk := hd h.clist;
				h.clist = tl h.clist;
				for( ; sl != nil; sl = tl sl)
					save = hd sl :: save;
				hostl = save;
				return chunk + " " + h.host;
			}
		}
		hostl = save;
	}
	return nil;
}
