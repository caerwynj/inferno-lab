
msgs := array[]  of {
	"freq",
	"keyon",
	"keyoff",
	"attack",
	"decay",
	"sustain",
	"release",
	"delay",
	"voice",
	"mix",
};



# serve a control file. takes a control channel and name for file
# reads ctrl message and float value. e.g. decay 1.0, freq 4.3
# can also take a list of allowable messages, so the filechan
# can respond with write errors if message isn't understood.
# 
ctlsrv(ctl: chan of (int, real), msg: list of int, name: string)
{
	fio := sys->file2chan("/chan", name);
	if(fio == nil)
		return;
	for(;;) alt {
	(nil, nil, nil, rc) := <-fio.read =>
		rc <-= (nil, nil);
	(nil, data, nil, wc) := <-fio.write =>
		if(wc == nil)
			continue;
		error := "";
		(n, flds) := sys->tokenize(string data, " \t\n\r");
		if(n != 2)
			error = "invalid arg";
		else if((m := lookup(hd flds)) != -1)
			error = "bad msg";
		else if(!valid(msg, m))
			error = "msg not accepted";
		else{
			val := real hd tl flds;
			ctl <-= (m, val);
		}
		if(error != nil)
			wc <-= (0, error);
		else
			wc <-= (len data, nil);
	}
}

lookup(s: string): int
{
	for(i:=0;i< len msgs; i++)
		if(s == msgs[i])
			return i;
	return -1;
}

valid(l : list of int, m: int): int
{
	for(;l != nil; l = tl l)
		if(hd l == m)
			return 1;
	return 0;
}