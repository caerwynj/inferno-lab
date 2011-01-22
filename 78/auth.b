implement Authenticate, Xymodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "xylib.m";
	xylib: Xylib;
	Value, Option: import xylib;

include "sh.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;

Authenticate: module {};

types(): string
{
	return "ff-ks-Cs-v";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	auth->init();
}

After, Before, Create: con 1<<iota;

run(r: chan of ref Value, opts: list of Option, args: list of ref Value)
{
	keyfile: string;
	alg: string;
	verbose: int;
	reply :=<- r;
	for(; opts != nil; opts = tl opts){
		case (hd opts).opt {
		'k' =>
			keyfile = (hd (hd opts).args).gets();
			if (keyfile != nil && ! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'C' =>
			alg = (hd (hd opts).args).gets();
		'v' =>
			verbose = 1;
		}
	}
	if(keyfile == nil)
		keyfile = "/usr/" + user() + "/keyring/default";
	cert := keyring->readauthinfo(keyfile);
	if (cert == nil) {
		sys->fprint(sys->fildes(2), "auth: cannot read %q: %r", keyfile);
		raise "fail:";
	}
	fd0 := (hd args).getfd();
	eu: string;
	(fd0, eu) = auth->client(alg, cert, fd0);
	if(fd0 == nil){
		sys->fprint(sys->fildes(2), "authentication failed: %s", eu);
		reply.send(nil);
	}
	reply.send(ref Value.F(fd0));
}

user(): string
{
	u := readfile("/dev/user");
	if (u == nil)
		return "nobody";
	return u;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}
