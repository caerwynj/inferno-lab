# limbo version (by saoret.one)
# of /contrib/rsc/dyndns.c from Russ Cox
implement Dyndns;

include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
	arg: Arg;
include "factotum.m";
	factotum: Factotum;
include "encoding.m";

Dyndns: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->print("usage: dyndns [-k keyspec] [-s server] host [ip]\n");
	raise "usage";
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg = load Arg Arg->PATH;
	factotum = load Factotum Factotum->PATH;
	base64 := load Encoding Encoding->BASE64PATH;
	
	arg->init(args);
	factotum->init();
	keyspec := "";
	server := "members.dyndns.org";
	while((c := arg->opt()) != 0)
		case c {
		's' =>
			server = use(arg->arg(), c);
		'k' =>
			keyspec = use(arg->arg(), c);
		* =>
			usage();
		}
	args = arg->argv();
	if (len args < 1 || len args > 2)
		usage();
	
	(user, password) := factotum->getuserpasswd(sys->sprint("proto=pass role=client service=dyndns server=%s %s", server, keyspec));
	auth := sys->sprint("%s:%s", user, password);
	(ok, cf) := sys->dial("net!"+server+"!http", "");
	if (ok<0){
		sys->print("dial: %s: %r\n", server);
		raise "dial";
	}

	ip := "";
	host := hd args;
	if (len args==2)
		ip = hd tl args;
	sys->fprint(cf.dfd, "GET /nic/update?hostname=%s&myip=%s HTTP/1.0\r\n"+
		"Host: %s\r\n"+
		"Authorization: Basic %s\r\n"+
		"User-Agent: stupid\r\n"+
		"\r\n", host, ip, server, base64->enc(array of byte auth));

	n := 0;
	buf := array[512] of byte;
	while((n = sys->read(cf.dfd, buf, len buf)) > 0)
		sys->write(sys->fildes(1), buf, n);
}

use(s: string, c: int): string
{
	if(s == nil)
		sys->print("missing value for -%c", c);
	return s;
}
