implement gettar;

include "sys.m";
	sys: Sys;
	print, sprint, fprint: import sys;
	stdin, stderr: ref sys->FD;
include "draw.m";
include "sh.m";
	sh: Sh;
	Context, Listnode: import sh;
include "arg.m";
	arg: Arg;

TBLOCK: con 512;	# tar logical blocksize
Header: adt{
	name: string;
	size: int;
	mode: int;
	mtime: int;
	skip: int;
};

gettar: module{
	init:   fn(nil: ref Draw->Context, nil: list of string);
};

Error(mess: string){
	fprint(stderr,"gettar: %s: %r\n",mess);
	raise "fail:error";
}
verbose := 0;
NBLOCK: con 20;		# blocking factor for efficient read
tarbuf := array[NBLOCK*TBLOCK] of byte;	# static buffer
nblock := NBLOCK;			# how many blocks of data are in tarbuf
recno := NBLOCK;			# how many blocks in tarbuf have been consumed
waitfd: ref Sys->FD;
getblock():array of byte{
	if(recno>=nblock){
		i := sys->read(stdin,tarbuf,TBLOCK*NBLOCK);
		if(i==0)
			return nil;
		if(i<0)
			Error("read error");
		if(i%TBLOCK!=0)
			Error("blocksize error");
		nblock = i/TBLOCK;
		recno = 0;
	}
	recno++;
	return tarbuf[(recno-1)*TBLOCK:recno*TBLOCK];
}


octal(b:array of byte):int{
	sum := 0;
	for(i:=0; i<len b; i++){
		bi := int b[i];
		if(bi==' ') continue;
		if(bi==0) break;
		sum = 8*sum + bi-'0';
	}
	return sum;
}

nullterm(b:array of byte):string{
	for(i:=0; i<len b; i++)
		if(b[i]==byte 0) break;
	return string b[0:i];
}

getdir():ref Header{
	dblock := getblock();
	if(len dblock==0)
		return nil;
	if(dblock[0]==byte 0)
		return nil;

	name := nullterm(dblock[0:100]);
	if(int dblock[345]!=0)
		name = nullterm(dblock[345:500])+"/"+name;

	magic := string(dblock[257:262]);
	if(magic[0]!=0 && magic!="ustar")
		Error("bad magic "+name);
	chksum := octal(dblock[148:156]);
	for(ci:=148; ci<156; ci++) dblock[ci] = byte ' ';
	for(i:=0; i<TBLOCK; i++)
		chksum -= int dblock[i];
	if(chksum!=0)
		Error("directory checksum error "+name);

	skip := 1;
	size := 0;
	mode := 0;
	mtime := 0;
	case int dblock[156]{
	'0' or '7' or 0 =>
		skip = 0;
		size = octal(dblock[124:136]);
		mode = 8r777 & octal(dblock[100: 108]);
		mtime = octal(dblock[136:148]);
	'1' =>
		fprint(stderr,"skipping link %s -> %s\n",name,string(dblock[157:257]));
	'2' or 's' =>
		fprint(stderr,"skipping symlink %s\n",name);
	'3' or '4' or '6' =>
		fprint(stderr,"skipping special file %s\n",name);
	'5' =>
		if(name[(len name)-1]=='/')
			checkdir(name+".");
		else
			checkdir(name+"/.");
	* =>
		Error(sprint("unrecognized typeflag %d for %s",int dblock[156],name));
	}
	return ref Header(name, size, mode, mtime, skip);
}

ctxt: ref Draw->Context;

init(ct: ref Draw->Context, argv: list of string){
	sys = load Sys Sys->PATH;
	sh = load Sh Sh->PATH;
	arg = load Arg Arg->PATH;

	ctxt = ct;
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);
	ofile: ref sys->FD;
	cmd: string;
	waitfd = sys->open("#p/"+string sys->pctl(0, nil)+"/wait", sys->OREAD);

	arg->init(argv);
	while((c := arg->opt()) != 0)
		case c {
		'v' => verbose = 1;
		* => sys->print("unkown option (%c)\n", c);
		}
	argv = arg->argv();
	cmd = hd argv;
	pid: int;
	while((file := getdir())!=nil){
		if(!file.skip){
			if(verbose)
				sys->print("%s\n", file.name);
			(ofile, pid) = dogetentry(file.name, cmd);
			checkdir(file.name);
		#	ofile = sys->create(file.name,sys->OWRITE,8r666);
			if(ofile==nil){
				fprint(stderr,"cannot create %s: %r\n",file.name);
				file.skip = 1;
			}
		}
		bytes := file.size;
		blocks := (bytes+TBLOCK-1)/TBLOCK;
		if(file.skip){
			for(; blocks>0; blocks--)
				getblock();
			continue;
		}

		for(; blocks>0; blocks--){
			buf := getblock();
			nwrite := bytes; if(nwrite>TBLOCK) nwrite = TBLOCK;
			if(sys->write(ofile,buf,nwrite)!=nwrite)
				Error(sprint("write error for %s",file.name));
			bytes -= nwrite;
		}
		ofile = nil;
		waitfor(pid);
		stat := sys->nulldir;
		stat.mode = file.mode;
		stat.mtime = file.mtime;
#		rc := sys->wstat(file.name,stat);
	}
}


checkdir(name:string)
{
#	sys->print("checkdir %s\n",  name );
	return;
	if(name[0]=='/')
		Error("absolute pathnames forbidden");
	(nc,compl) := sys->tokenize(name,"/");
	path := "";
	while(compl!=nil){
		comp := hd compl;
		if(comp=="..")
			Error(".. pathnames forbidden");
		if(nc>1){
			if(path=="")
				path = comp;
			else
				path += "/"+comp;
			(rc,stat) := sys->stat(path);
			if(rc<0){
				fd := sys->create(path,Sys->OREAD,Sys->DMDIR+8r777);
				if(fd==nil)
					Error(sprint("cannot mkdir %s",path));
				fd = nil;
			}else if(stat.mode&Sys->DMDIR==0)
				Error(sprint("found non-directory at %s",path));
		}
		nc--; compl = tl compl;
	}
}

exec(sync: chan of int, file: string, cmd : string, out: array of ref Sys->FD)
{
#	file := cmd;
#	if(len file<4 || file[len file-4:]!=".dis")
#		file += ".dis";

	sys->pctl(Sys->FORKFD, nil);
	sys->dup(out[1].fd, 0);
	out[0] = nil;
	out[1] = nil;
	sync <-= sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);
	co := Context.new(ctxt);
	co.set("file", ref Listnode(nil, file) :: nil);
	(cc, nil) := sh->parse(cmd);
	co.run(ref Listnode(cc, nil) :: nil, 1);
#	c := load Command file;
#	if(c == nil) {
#		err := sys->sprint("%r");
#		if(file[0]!='/' && file[0:2]!="./"){
#			c = load Command "/dis/"+file;
#			if(c == nil)
#				err = sys->sprint("%r");
#		}
#		if(c == nil){
#			# debug(sys->sprint("file %s not found\n", file));
#			sys->fprint(sys->fildes(2), "%s: %s\n", cmd, err);
#			return;
#		}
#	}
#	c->init(nil, argl);
}

dogetentry(file: string, cmd: string): (ref Sys->FD, int)
{
	p := array[2] of ref Sys->FD;

	if(sys->pipe(p) < 0)
		return (nil, 0);
	sync := chan of int;
	spawn exec(sync, file, cmd, (array[2] of ref Sys->FD)[0:] = p);
	pid := <-sync;
	p[1] = nil;
	return (p[0], pid);
}

waitfor(pid: int)
{
	buf := array[sys->WAITLEN] of byte;
	status := "";
	for(;;){
		n := sys->read(waitfd, buf, len buf);
		if(n < 0) {
			sys->fprint(stderr, "sh: read wait: %r\n");
			return;
		}
		status = string buf[0:n];
		if(status[len status-1] != ':')
			sys->fprint(stderr, "%s\n", status);
		who := int status;
		if(who != 0) {
			if(who == pid)
				return;
		}
	}
}
