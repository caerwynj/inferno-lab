implement Signal;

include "sys.m";
	sys: Sys;
	read: import sys;
include "signal.m";

samplerate := 22050.0;
channels := 1;
gain := 1.0;
inputs: array of real;
outputs: array of real;
nB := 1;
nA := 1;
a: array of real;
b: array of  real;
fd: ref Sys->FD;
filename:= "";

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	b = array[nB] of {* => 1.0};
	a = array[nA] of {* => 1.0};
	inputs = array[nB] of {* => 0.0};
	outputs = array[nA] of {* => 0.0};
	config("");
}

getsample(): real
{
	buf:= array[2] of byte;
	if(fd == nil)
		return -1.0;
	read(fd, buf, 2);
	n := (int buf[1]<<24 | int buf[0] << 16) >> 16;
	return real n;
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

# next sample for n channels
tickFrame(): array of real
{
	out :=array[channels] of real;
	for(i:=0;i<channels;i++) {
		out[i] = tick(getsample());
	}
	return out;
}

config(s: string)
{
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
			fd = sys->open(filename, Sys->OREAD);
			if(fd == nil)
				sys->fprint(sys->fildes(2), "invalid file %s\n", filename);
		}
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
}
