implement Signal;

include "sys.m";
	sys: Sys;
include "signal.m";
include "dsp.m";
	dsp: Dsp;

samplerate := 22050.0;
bps := 2;
channels := 1;
gain := 1.0;
inputs: array of real;
outputs: array of real;
nB := 1;
nA := 1;
a: array of real;
b: array of  real;
fd: ref Sys->FD;		# data file
ctl: ref Sys->FD;		# control file
filename:= "";

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	dsp = load Dsp Dsp->PATH;

	b = array[nB] of {* => 1.0};
	a = array[nA] of {* => 1.0};
	inputs = array[nB] of {* => 0.0};
	outputs = array[nA] of {* => 0.0};
	config("");
}

read(n: int): array of byte
{
	nsamples := n/(bps*channels);
	out := getsamples(nsamples);
	for(i:=0;i<len out;i++)
		out[i] = tick(out[i]);
	return dsp->real2pcm(out);
}

getsamples(n: int): array of real
{
	buf:= array[n*2] of byte;
	b: array of byte;
	out:= array[n] of real;
	nb := sys->read(fd, buf, len buf);
	b=buf[0:nb];
	for(i:=0;i<nb/2;i++){
		out[i] = real ((int b[1]<<24 | int b[0] << 16) >> 16);
		b = b[2:];
	}
	return out[0:i];
}

tick(sample: real): real
{
	i: int;
	outputs[0] = 0.0;
	inputs[0] = gain * sample;
	for (i=nB-1; i>0; i--) {
		outputs[0] += b[i] * inputs[i];
		inputs[i] = inputs[i-1];
	}
	outputs[0] += b[0] * inputs[0];

	for (i=nA-1; i>0; i--) {
		outputs[0] += -a[i] * outputs[i];
		outputs[i] = outputs[i-1];
	}

	return outputs[0];
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	if(n > 0){
		case hd flds {
		"acoef" =>
			nA = n - 1;
			a = array[nA] of real;
			outputs = array[nA] of {* => 0.0};
			i := 0;
			for(flds = tl flds; flds != nil; flds = tl flds)
				a[i++] =real hd flds;
		"bcoef" =>
			nB = n - 1;
			b = array[nB] of real;
			inputs = array[nB] of {* => 0.0};
			i := 0;
			for(flds = tl flds; flds != nil; flds = tl flds)
				b[i++] = real hd flds;
		"gain" =>
			gain = real hd tl flds;
		"source" =>
			filename = hd tl flds;
			e = initsource(filename);
		* =>
			e = ctlwrite(s);
		}
	}
	# scale coefficients by a[0] if necessary
	if (a[0] != 1.0) {
		for (i:=0; i<nB; i++)
			b[i] /= a[0];
		for (i=0; i<nA; i++)
			a[i] /= a[0];
	}
	configstr = sys->sprint("rate %d\nchans %d\ngain %g\nsource %s", 
		int samplerate, channels, gain, filename);
	configstr += "\nacoef ";
	for(i:=0; i < nA; i++)
		configstr += sys->sprint("%g ", a[i]);
	configstr += "\nbcoef ";
	for(i=0; i < nB; i++)
		configstr += sys->sprint("%g ", b[i]);
	configstr += "\n";
	return e;
}

initsource(file: string): string
{
	ctl = sys->open(file + "/clone", Sys->ORDWR);
	if(ctl == nil)
		return sys->sprint("invalid clone file %s\n", file + "/clone");
	buf:= array[10] of byte;
	n:= sys->read(ctl, buf, len buf);
	datafile := file + "/" + string buf[:n] + "/data";
	fd = sys->open(datafile, Sys->OREAD);
	if(fd == nil)
		return sys->sprint("invalid data file %s\n", datafile);
	return nil;
}

ctlwrite(s: string): string
{
	n := sys->fprint(ctl, "%s", s);
	if(n < 0)
		return sys->sprint("%r");
	return nil;
}