implement Dsp;

include "sys.m";
	sys: Sys;
include "dsp.m";

init()
{
	sys = load Sys Sys->PATH;
}

real2pcm(v: array of real): array of byte
{
	b:=array[len v *2] of byte;
	j:=0;
	for(i:=0;i<len v;i++){
		if(v[i] > 32767.0)
			v[i] = 32767.0;
		else if(v[i] < -32767.0)
			v[i] = -32767.0;
		b[j++] = byte v[i];
		b[j++] = byte (int v[i] >>8);
	}
	return b;
}

Sig.open(file: string): ref Sig
{
	sig := ref Sig;
	sig.ctl = sys->open(file + "/clone", Sys->ORDWR);
	if(sig.ctl == nil)
		return nil;
	buf:= array[10] of byte;
	n:= sys->read(sig.ctl, buf, len buf);
	datafile := file + "/" + string buf[:n] + "/data";
	sig.data = sys->open(datafile, Sys->OREAD);
	if(sig.data == nil)
		nil;
	return sig;
}

Sig.read(sig: self ref Sig, nsamples: int): array of real
{
	buf:= array[nsamples*2] of byte;
	b: array of byte;
	out:= array[nsamples] of real;
	nb := sys->read(sig.data, buf, len buf);
	b=buf[0:nb];
	for(i:=0;i<nb/2;i++){
		out[i] = real ((int b[1]<<24 | int b[0] << 16) >> 16);
		b = b[2:];
	}
	return out[0:i];
}

Sig.readbytes(sig: self ref Sig, nbyte: int): array of byte
{
	buf := array[nbyte] of byte;
	nb := sys->read(sig.data, buf, len buf);
	return buf[:nb];
}
