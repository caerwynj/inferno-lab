implement Xymodule;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
include "xylib.m";
	xylib: Xylib;
	Value, Option: import xylib;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;

types(): string
{
	return "ff";
}

init()
{
	sys = load Sys Sys->PATH;
	xylib = load Xylib Xylib->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
}

run(r: chan of ref Value, nil: list of Option, args: list of ref Value)
{
	reply :=<- r;
	sys->pipe(p := array[2] of ref Sys->FD);
	reply.send(ref Value.F(p[1]));
	fd := (hd args).getfd();
	spawn tmsgreader(p[0], fd, p1 := chan[1] of int, p2 := chan[1] of int);
	spawn rmsgreader(fd, p[0], p2, p1);
}

tmsgreader(cfd, sfd: ref Sys->FD, p1, p2: chan of int)
{
	p1 <-= sys->pctl(0, nil);
	m: ref Tmsg;
	do{
		m = Tmsg.read(cfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(sfd, d, len d) != len d)
			sys->print("tmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
}

rmsgreader(sfd, cfd: ref Sys->FD, p1, p2: chan of int)
{
	p1 <-= sys->pctl(0, nil);
	m: ref Rmsg;
	do{
		m = Rmsg.read(sfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(cfd, d, len d) != len d)
			sys->print("rmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
}

kill(pid: int)
{
	if ((fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
}
