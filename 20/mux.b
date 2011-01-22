implement Muxm;

include "sys.m";
	sys: Sys;
	fprint, fildes: import sys;
include "mux.m";

new(): ref Mux
{
	mux := ref Mux((chan[1] of int), 0, 0, nil, 0, (chan of int));
	mux.wait  = array[256] of ref Muxrpc;
	return mux;
}

Mux.rpc(mux: self ref Mux, tx: array of byte): array of byte
{
	tag: int;
	r, r2: ref Muxrpc;
	p: array of byte;

	r = ref Muxrpc((chan of int), nil, 0);

	mux.lock();
	tag = mux.gettag(r);
	mux.unlock();
	
	if(tag < 0 || settag(tx, tag) < 0 || mux.send(tx) < 0) {
		mux.lock();
		mux.puttag(r, tag);
		mux.unlock();
		return nil;
	}

	mux.lock();
	r.sleeping = 1;
	mux.nsleep++;

	while(mux.muxer && r.p == nil){
		mux.unlock();
		<-r.r;
		mux.lock();  # TODO: we may not be at the front of the queue so we
	# may be waiting for another thread to become muxer
	# even though we're ready to go. (we could implement rsleep, rwakeup)
	}
	mux.nsleep--;
	r.sleeping = 0;

	if(r.p == nil){
		if(mux.muxer)
			exit;
		mux.muxer = 1;
		while(r.p == nil) {
			mux.unlock();
			p = mux.recv();
			if(p != nil)
				tag = gettag(p);
			else
				tag = ~0;
			mux.lock();
			if(p == nil)
				break;
			if(tag < 0 || tag >= 256 || mux.wait[tag] == nil)
				continue;
			r2 = mux.wait[tag];
			r2.p = p;
			if(r2 != r)
				r2.r <-= 1;

		}
		mux.muxer = 0;
			
		if(mux.nsleep){
			for(i:=0; i<256; i++)	
				if(mux.wait[i] != nil && mux.wait[i].sleeping)
					break;
			if(i == 256)
				fprint(fildes(2), "mux: nsleep botch\n");
			else
				mux.wait[i].r <-= 1;
		}
	}
	p = r.p;
	mux.puttag(r, tag);
	mux.unlock();
	return p;
}


Mux.gettag(z: self ref Mux, r: ref Muxrpc): int
{
	for(;;){
		while(z.ntag == 256)
			<-z.tagrend;
		for(i:=0; i<256; i++)
			if(z.wait[i] == nil){
				z.ntag++;
				z.wait[i] = r;
				return i;
			}
		fprint(fildes(2), "mux: ntag botch\n");
	}
}

Mux.puttag(z: self ref Mux, r: ref Muxrpc, tag: int)
{
	z.wait[tag] = nil;
	z.ntag--;
#	rwakeup(&z->tagrend);  # what if no one is waiting?
}

Mux.lock(m: self ref Mux)
{
	m.lk <-= 0;
}

Mux.unlock(m: self ref Mux)
{
	<-m.lk;
}

Mux.send(m: self ref Mux, p: array of byte): int
{
	return 0;
}

Mux.recv(m: self ref Mux): array of byte
{
	return nil;
}

gettag(p: array of byte): int
{
	return 0;
}

settag(p: array of byte, tag: int): int
{
	return 0;
}
