implement Command;

include "sh.m";
include "sys.m";
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

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

init(nil: ref Draw->Context, args: list of string)
{
	sys := load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;

	args = tl args;
	if(len args != 2){
		sys->fprint(sys->fildes(2), "usage: intermediate n\n");
		exit;
	}
	R := int hd args;
	prefix := hd tl args;
	fds := array[R] of ref Sys->FD;
	for(i := 0; i < R; i++){
		fds[i] = sys->create(prefix + string i, Sys->ORDWR, 8r666);
	}

	io := bufio->fopen(sys->fildes(0), Sys->OREAD);
	while((s := io.gets('\n')) != nil){
		(n, f) := sys->tokenize(s, " \t\n\r");
		if(n != 2)
			continue;
		h := fun1(hd f, R);
		sys->fprint(fds[h], "%s", s);
	}
}
