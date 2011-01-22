implement Dsfs;

include "sys.m";
	sys: Sys;
	pread, pwrite: import sys;

include "draw.m";
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Styxserver, Navigator, Navop, readstr: import styxservers;
	nametree: Nametree;
	Tree: import nametree;

include "arg.m";
	arg: Arg;

include "string.m";
	str : String;

Dsfs: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

tree: ref Tree;
treeop: chan of ref Navop;
srv: ref Styxserver;

Cfgstr := "";

Fmirror,
Fcat,
Finter,
Fpart:	con iota;

Blksize: con 8*1024;
Maxconf: con 1024;

Nfsdevs: con 64;
Ndevs: con 8;

Qroot, Qctl, Qfirst: con big iota;	# paths

Eio: con "IO error";
Enonexist: con "File does not exist";
Egreg: con "greg";
Enodev: con "No more devices";

Fsdev: adt {
	typ: int;
	name: string;
	start:	big;
	size:	big;
	path: big;
	ndevs:	int;
 	iname:	array of string;
	idev:		array of ref Chan;
	isize:		array of big;
};

Chan: adt {
	fd: 	ref Sys->FD;
};

fsdev:	array of ref Fsdev;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	styxservers->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	str = load String String->PATH;

	arg = load Arg Arg->PATH;
	arg->setusage("dsfs [-a|-b|-ac|-bc] [-D]  mountpoint");
	arg->init(args);
	flags := Sys->MREPL;
	while((o := arg->opt()) != 0)
		case o {
		'a' =>	flags = Sys->MAFTER;
		'b' =>	flags = Sys->MBEFORE;
		'D' =>	styxservers->traceset(1);
		* =>		arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();
	mountpt := hd args;

	sys->pctl(Sys->NEWPGRP, nil);	

	fsdev = array[Nfsdevs] of ref Fsdev;
	fds := array[2] of ref Sys->FD;
	if(sys->pipe(fds) < 0)
		error(sys->sprint("can't create pipe: %r"));

	(tree, treeop) = nametree->start();
	tree.create(Qroot, dir(".", 8r555|Sys->DMDIR, Qroot, big 0));
	tree.create(Qroot, dir("ctl", 8r666, Qctl, big 0));
	tchan: chan of ref Tmsg;
	(tchan, srv) = Styxserver.new(fds[0], Navigator.new(treeop), Qroot);
	fds[0] = nil;
	pidc := chan of int;
	spawn server(tchan, srv, pidc);
	<-pidc;

	if(sys->mount(fds[1], nil, mountpt, flags, nil) < 0)
		error(sys->sprint("can't mount dsfs: %r"));

}
server(tchan: chan of ref Tmsg, srv: ref Styxserver, pidc: chan of int)
{
	pidc <-= sys->pctl(0, 1::2::srv.fd.fd::nil);
	while((gm := <-tchan) != nil) {
# we are  calling ourselves recursively so spawn a proc for each call.
# TODO handle flush by killing the procs
		pick m := gm {
		Read =>
			spawn mread(m);
		Write =>
			spawn mwrite(m);
		* =>
			srv.default(gm);
		}
	}
	tree.quit();
}

dir(name: string, perm: int, qid: big, length: big): Sys->Dir
{
	d := sys->zerodir;
	d.name = name;
	d.uid = "caerwyn";
	d.gid = "caerwyn";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	d.length = length;
	return d;
}

catio(mp: ref Fsdev, isread: int, a: array of byte, n: int, off: big): int
{
	mc: ref Chan;
	l, wl, res: int;
	res = n;
	for(i := 0; n >= 0 && i < mp.ndevs; i++) {
		mc = mp.idev[i];
		if(off > mp.isize[i]){
			off -= mp.isize[i];
			continue;
		}
		if(off + big n > mp.isize[i])
			l = int (mp.isize[i] - off);
		else
			l = n;
		if(isread)
			wl = pread(mc.fd, a, l, off);
		else
			wl = pwrite(mc.fd, a, l, off);
		if(wl != l)
			error("bullshit");
		a = a[l:];
		off = big 0;
		n -= l;
	}
	return res - n;
} 

interio(mp: ref Fsdev, isread: int, a: array of byte, n: int, off: big): int
{
	mc: ref Chan;
	l, wl, wsz: int;
	woff, blk, mblk: big;
	boff, res: int;

	blk = off / big Blksize;
	boff = int (off % big Blksize);
	wsz = Blksize - boff;
	res = n;
	while(n > 0){
		i := int (blk % big mp.ndevs);
		mc = mp.idev[i];
		mblk = blk / big mp.ndevs;
		woff = mblk * big Blksize + big boff;
		if(n > wsz)
			l = wsz;
		else
			l = n;
		if(isread)
			wl = pread(mc.fd, a , l, woff);
		else
			wl = pwrite(mc.fd, a, l, woff);
		if(wl != l || l == 0)
			error(Eio);
		a = a[l:];
		n -= l;
		blk++;
		boff = 0;
		wsz = Blksize;
	}
	return res;
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	exit;
}

path2dev(i:  int, mustexist: int): ref Fsdev
{
	if (i < 0 || i >= len fsdev)
		error("bug: bad index in devfsdev");
	if (mustexist && fsdev[i].name == nil)
		error(Enonexist);

	if (fsdev[i].name == nil)
		return nil;
	else
		return fsdev[i];
}

mconfig(a: array of byte)
{
	parm := str->unquoted(string a);
	mp := devalloc();
	if(hd parm == "mirror")
		mp.typ = Fmirror;
	else if(hd parm == "part")
		mp.typ = Fpart;
	else if(hd parm == "inter")
		mp.typ = Finter;
	else if(hd parm == "cat")
		mp.typ = Fcat;
	parm = tl parm;
	mp.name = hd parm;
	parm = tl parm;
	for(i := 0; parm != nil; parm = tl parm){
		mp.iname[i] = hd parm;
		mp.idev[i] = namec(mp.iname[i], Sys->ORDWR);
		if(mp.idev[i] == nil)
			error(Egreg);
		mp.ndevs++;
		i++;
	}
	setdsize(mp);
	Cfgstr += string a;
	tree.create(Qroot, dir(mp.name, 8r666, mp.path, mp.size));
}

namec(f: string, mode: int): ref Chan
{
	c := ref Chan;
	c.fd = sys->open(f, mode);
	return c;
}

mread(m: ref Tmsg.Read)
{
	(c, err) := srv.canread(m);
	if(c == nil){
		srv.reply(ref Rmsg.Error(m.tag, err));
		return;
	}
	if(c.qtype & Sys->QTDIR){
		srv.default(m);
		return;
	}
	if(c.path == Qctl){
		srv.reply(readstr(m, Cfgstr));
		return;
	}
	mp := path2dev(int(c.path -  Qfirst), 1);

	if(m.offset >= mp.size){
		srv.reply(ref Rmsg.Read(m.tag, nil));
		return;
	}
	if(m.offset + big m.count > mp.size){
		srv.reply(ref Rmsg.Read(m.tag, nil));
		return;
	}
	if(m.count == 0){
		srv.reply(ref Rmsg.Read(m.tag, nil));
		return;
	}
	case(mp.typ){
	Fmirror =>
		for(i := 0; i < mp.ndevs; i++){
			mc := mp.idev[i];
			a := array[m.count] of byte;
			l := pread(mc.fd, a, m.count, m.offset);
			if(l >= 0){
				srv.reply(ref Rmsg.Read(m.tag, a[0:l]));
				break;
			}
		}
		if(i == mp.ndevs)
			error(Eio);
	Fcat =>
		a := array[m.count] of byte;
		res := catio(mp, 1, a, m.count, m.offset);
		srv.reply(ref Rmsg.Read(m.tag, a[0:res]));
	Finter =>
		a := array[m.count] of byte;
		res := catio(mp, 1, a, m.count, m.offset);
		srv.reply(ref Rmsg.Read(m.tag, a[0:res]));
	Fpart =>
		off := m.offset + mp.start;
		mc := mp.idev[0];
		a := array[m.count] of byte;
		l := pread(mc.fd, a, m.count, off);
		srv.reply(ref Rmsg.Read(m.tag, a[0:l]));
	}
}

mwrite(m: ref Tmsg.Write)
{
	(c, err) := srv.canwrite(m);
	if(c == nil){
		srv.reply(ref Rmsg.Error(m.tag, err));
		return;
	}
	if(c.path == Qctl){
		mconfig(m.data);
		srv.reply(ref Rmsg.Write(m.tag, len m.data));
		return;
	}	
	mp := path2dev(int(c.path - Qfirst), 1);

	if(m.offset >= mp.size){
		srv.reply(ref Rmsg.Write(m.tag, 0));
		return;
	}
	if(m.offset + big len m.data > mp.size){
		srv.reply(ref Rmsg.Write(m.tag, 0));
		return;
	}
	if(len m.data == 0){
		srv.reply(ref Rmsg.Write(m.tag, 0));
		return;
	}
	case(mp.typ){
	Fmirror =>
		l: int;
		for(i := mp.ndevs - 1; i>= 0; i--){
			mc := mp.idev[i];
			l = pwrite(mc.fd, m.data, len m.data, m.offset);
		}
		srv.reply(ref Rmsg.Write(m.tag, l));
	Fcat =>
		res := catio(mp, 0, m.data, len m.data, m.offset);
		srv.reply(ref Rmsg.Write(m.tag, res));
	Finter =>
		res := interio(mp, 0, m.data, len m.data, m.offset);
		srv.reply(ref Rmsg.Write(m.tag, res));
	Fpart =>
		off := m.offset + mp.start;
		mc := mp.idev[0];
		l := pwrite(mc.fd, m.data, len m.data, off);
		srv.reply(ref Rmsg.Write(m.tag, l));
	}

}

setdsize(mp: ref Fsdev)
{

	if (mp.typ != Fpart){
		mp.start= big 0;
		mp.size = big 0;
	}
	for (i := 0; i < mp.ndevs; i++){
		mc := mp.idev[i];
		if(mc == nil)
			continue;
		(n, d) := sys->fstat(mc.fd);
		mp.isize[i] = d.length;
		case(mp.typ){
		Fmirror =>
			if (mp.size == big 0 || mp.size > d.length)
				mp.size = d.length;
		Fcat =>
			mp.size += d.length;
		Finter =>
			# truncate to multiple of Blksize
			d.length = (d.length & ~big(Blksize-1));
			mp.isize[i] = d.length;
			mp.size += d.length;
		Fpart =>
			# should raise errors here?
			if (mp.start > d.length)
				mp.start = d.length;
			if (d.length < mp.start + mp.size)
				mp.size = d.length - mp.start;
		}
	}
}

devalloc(): ref Fsdev
{
	for(i := 0; i<len fsdev; i++)
		if(fsdev[i] == nil)
			break;
	if(i == len fsdev)
		error(Enodev);
	fsdev[i] = ref Fsdev(0, nil, big 0, big 0, big 0, 0, nil, nil, nil);
	fsdev[i].iname = array[Ndevs] of string;
	fsdev[i].idev = array[Ndevs] of ref Chan;
	fsdev[i].isize = array[Ndevs] of big;
	fsdev[i].path =  Qfirst + big i;
	return fsdev[i];
}
