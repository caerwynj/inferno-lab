implement Automnt;
include "sys.m";
	sys: Sys;
include "draw.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Ebadfid, Enotfound, Eopen, Einuse: import Styxservers;
	Styxserver, readbytes, Navigator, Fid: import styxservers;

	nametree: Nametree;
	Tree: import nametree;

Automnt: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

Qroot: con big 16rfffffff;

badmodule(p: string)
{
	sys->fprint(sys->fildes(2), "cannot load %s: %r\n", p);
	raise "fail:bad module";
}
DEBUG: con 0;

Entry: adt {
	refcount: int;
	path: big;
};
refcounts := array[10] of Entry;
tree: ref Tree;
nav: ref Navigator;

# TODO: Maybe make this an argument?
AMNTPREFIX := "/amnt/";

uniq: int;

worker(gm: ref Styx->Tmsg, srv: ref Styxserver, tree: ref Tree)
{
	e := handlemsg(gm, srv, tree);
	if (e != nil)
		srv.reply(ref Rmsg.Error(gm.tag, e));
}

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	styx = load Styx Styx->PATH;
	if (styx == nil)
		badmodule(Styx->PATH);
	styx->init();
	styxservers = load Styxservers Styxservers->PATH;
	if (styxservers == nil)
		badmodule(Styxservers->PATH);
	styxservers->init(styx);
 
	nametree = load Nametree Nametree->PATH;
	if (nametree == nil)
		badmodule(Nametree->PATH);
	nametree->init();

	navop: chan of ref Styxservers->Navop;
	(tree, navop) = nametree->start();
	nav = Navigator.new(navop);
	(tchan, srv) := Styxserver.new(sys->fildes(0), nav, Qroot);

	tree.create(Qroot, dir(".", Sys->DMDIR | 8r555, Qroot));

	for (;;) {
		gm := <-tchan;
		if (gm == nil) {
			tree.quit();
			exit;
		}
		spawn worker(gm, srv, tree);
	}
}

walk1(c: ref Fid, name: string): string
{
	if (name == ".."){
		if (c.path != Qroot)
			decref(c.path);
		c.walk(Sys->Qid(Qroot, 0, Sys->QTDIR));
	} else if (c.path == Qroot) {
		(d, nil) := nav.walk(c.path, name);
		if (d == nil) {
			d = addentry(name);
			if (d == nil)
				return Enotfound;
		} else
			incref(d.qid.path);
		c.walk(d.qid);
	} else
		return Enotfound;
	return nil;
}

handlemsg(gm: ref Styx->Tmsg, srv: ref Styxserver, nil: ref Tree): string
{
	pick m := gm {
	Walk =>
		c := srv.getfid(m.fid);
		if(c == nil)
			return Ebadfid;
		if(c.isopen)
			return Eopen;
		if(m.newfid != m.fid){
			nc := srv.newfid(m.newfid);
			if(nc == nil)
				return Einuse;
			c = c.clone(nc);
			incref(c.path);
		}
		qids := array[len m.names] of Sys->Qid;
		oldpath := c.path;
		oldqtype := c.qtype;
		incref(oldpath);
		for (i := 0; i < len m.names; i++){
			err := walk1(c, m.names[i]);
			if (err != nil){
				if(m.newfid != m.fid){
					decref(c.path);
					srv.delfid(c);
				}
				c.path = oldpath;
				c.qtype = oldqtype;
				if(i == 0)
					return err;
				srv.reply(ref Rmsg.Walk(m.tag, qids[0:i]));
				return nil;
			}
			qids[i] = Sys->Qid(c.path, 0, c.qtype);
		}
		decref(oldpath);
		srv.reply(ref Rmsg.Walk(m.tag, qids));
	Clunk =>
		c := srv.clunk(m);
		if (c != nil && c.path != Qroot)
			decref(c.path);
	* =>
		srv.default(gm);
	}
	return nil;
}

mountit(dest: ref Sys->FD, foo :string)
{
	result := sys->mount(dest,  nil, foo, Sys->MREPL, nil);
	if(result < 0)
		sys->fprint(sys->fildes(2), "you suck -  %d %r\n", result);
}

# passthe hostname we are trying to connect to
connect(name: string) :int
{
	addr := "tcp!"+name+"!1127";
	
	(ok, dest) := sys->dial(addr, nil);
	if(ok < 0){
		sys->fprint(sys->fildes(2), "cserv: can't dial %s: %r\n", addr);
		return -1;
	}
	
	foo := AMNTPREFIX + name;

	mountit(dest.dfd, foo);
	
	return 1;
}

addentry(name: string): ref Sys->Dir
{
	for (i := 0; i < len refcounts; i++)
		if (refcounts[i].refcount == 0)
			break;
	if (i == len refcounts) {
		refcounts = (array[len refcounts * 2] of Entry)[0:] = refcounts;
		for (j := i; j < len refcounts; j++)
			refcounts[j].refcount = 0;
	}
	d := dir(name, Sys->DMDIR|8r555, big i | (big uniq++ << 32));
	tree.create(Qroot, d);
	refcounts[i] = (1, d.qid.path);
	
	result := connect(name);
	
	if (result < 0)
		return nil;
		
	return ref d;
}

incref(q: big)
{
	id := int q;
	if (id >= 0 && id < len refcounts){
		refcounts[id].refcount++;
	}
}

decref(q: big)
{
	id := int q;
	if (id >= 0 && id < len refcounts){
		if (--refcounts[id].refcount == 0)
			tree.remove(refcounts[id].path);
	}
}

Blankdir: Sys->Dir;
dir(name: string, perm: int, qid: big): Sys->Dir
{
	d := Blankdir;
	d.name = name;
	d.uid = "me";
	d.gid = "me";
	d.qid.path = qid;
	if (perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = perm;
	return d;
}
