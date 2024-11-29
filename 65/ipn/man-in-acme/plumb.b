implement Plumb;

include "sys.m";
	sys: Sys;

include "draw.m";

include "arg.m";
	arg: Arg;

include "plumbmsg.m";
	plumbmsg: Plumbmsg;
	Msg, Attr: import plumbmsg;

include "workdir.m";
	workdir: Workdir;

Plumb: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

m : ref Msg;
usage()
{
	sys->fprint(stderr(), "Usage: plumb [-s src] [-d dest] [-D dir] [-k kind] [-a name val] -i | ... data ...\n");
	raise "fail:usage";
}

gather()
{
	buf := array[8192] of byte;
	n, ndata: int;
	
	ndata = 0;
	m.data = nil;
	while((n = sys->read(sys->fildes(0), buf, len buf)) > 0){
		b := array[ndata + len buf] of byte;
		if(b == nil){
			err(sys->sprint("alloc failed: %r\n"));
			raise "alloc";
		}
		if (ndata > 0)
			b[0:] = m.data[0:ndata];
		b[ndata:] = buf[0:n];
		m.data = b[0:ndata+n];
		ndata += n;
	}

	if (n < 0){
		err(sys->sprint("i/o error on input: %r\n"));
		raise "read";
	}
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;
	if(arg == nil)
		nomod(Arg->PATH);
	plumbmsg = load Plumbmsg Plumbmsg->PATH;
	if(plumbmsg == nil)
		nomod(Plumbmsg->PATH);
	workdir = load Workdir Workdir->PATH;
	if(workdir == nil)
		nomod(Workdir->PATH);

	if(plumbmsg->init(1, nil, 0) < 0)
		err(sys->sprint("can't connect to plumb: %r"));

	attrs: list of ref Attr;
	input := 0;
	m = ref Msg("plumb", nil, workdir->init(), "text", nil, nil);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		's' =>
			m.src = use(arg->arg(), c);
		'd' =>
			m.dst = use(arg->arg(), c);
		'D' =>
			m.dir = use(arg->arg(), c);
		'i' =>
			input++;
		't' or 'k'=>
			m.kind = use(arg->arg(), c);
		'a' =>
			name := use(arg->arg(), c);
			val := use(arg->arg(), c);
			attrs = tack(attrs, ref Attr(name, val));
		* =>
			usage();
		}
	args = arg->argv();
	if((input && len args > 0) || (!input && len args < 1))
		usage();
	if(input){
		gather();
		(notfound, nil) := plumbmsg->lookup(plumbmsg->string2attrs(m.attr), "action");
		if(notfound){
			tack(attrs, ref Attr("action", "showdata"));
		}
		m.attr = plumbmsg->attrs2string(attrs);
		if(m.send() < 0){
			err(sys->sprint("can't send message: %r\n"));
			raise "error";
		}
		exit;
	}
	
	nb := 0;
	for(a := args; a != nil; a = tl a)
		nb += len array of byte hd a;
	nb += len args;
	buf := array[nb] of byte;
	nb = 0;
	for(a = args; a != nil; a = tl a){
		b := array of byte hd a;
		buf[nb++] = byte ' ';
		buf[nb:] = b;
		nb += len b;
	}
	m.data = buf[1:];
	m.attr = plumbmsg->attrs2string(attrs);
	if(m.send() < 0)
		err(sys->sprint("can't plumb message: %r"));
}

tack(l: list of ref Attr, v: ref Attr): list of ref Attr
{
	if(l == nil)
		return v :: nil;
	return hd l :: tack(tl l, v);
}

use(s: string, c: int): string
{
	if(s == nil)
		err(sys->sprint("missing value for -%c", c));
	return s;
}

nomod(m: string)
{
	err(sys->sprint("can't load %s: %r\n", m));
}

err(s: string)
{
	sys->fprint(stderr(), "plumb: %s\n", s);
	raise "fail:error";
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

