implement Signal;

include "sys.m";
	sys: Sys;
include "signal.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

samplerate := 22050.0;
pitch := 440.0;
channels := 1;
data: array of real;
bps:=2;
rate:=1.0;
time := 0.0;
swab := 0;

init(nil: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	data = array[2] of {* => 0.0};
	config("pitch 440.0");
}

read(n: int): array of byte
{
	return real2pcm(tickBlock(n/(bps*channels)));
}

# next sample for n channels
tickFrame(): array of real
{
	out :=array[channels] of real;
	index : int;
	alpha : real;

	while(time < 0.0)
		time += real len data;
	while(time >= real len data)
		time -= real len data;
	index = int time;
	alpha = time - real index;
	index *= channels;
	for(i:=0; i<channels; i++){
		out[i] = data[index%(len data)];
		out[i] += (alpha * (data[(index+channels)%(len data)] - out[i]));
		index++;
	}
	time += rate;
	return out;
}

config(s: string): string
{
	e: string = nil;
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"pitch" =>
		pitch = real hd tl flds;
		rate = real(len data) * pitch / samplerate;
	"file" =>
		ndata := readfile(hd tl flds);
		if(ndata == nil)
			e = "bad source";
		else
			data = ndata;
	}
	configstr = sys->sprint("rate %d\nchans %d\nfreq %g\n", int samplerate, channels, pitch);
	return e;
}

readfile(file: string): array of real
{
	n := 0;
	y := array[8] of real;
	io := bufio->open(file, bufio->OREAD);
	if(io == nil)
		return nil;
	for(;;){
	 	(b, eof) := getw(io);
		if(eof)
			break;
		if(n >= len y)
			y = (array[len y * 2] of real)[0:] = y;
		y[n++] = real b;
	}
	return y[0:n];
}

getw(io: ref Iobuf): (int, int)
{
	b:= array[2] of int;
	for(i:=0;i<2;i++){
		b[i] = io.getb();
		if(b[i] == bufio->EOF)
			return (0, 1);
	}
	if(swab)
		n := b[1]<<24 | b[0] << 16;
	else 
		n = b[0]<<24 | b[1] << 16;
	return (n >> 16, 0);
}

tickBlock(n: int): array of real
{
	buf := array[n] of real;
	b := buf[0:];
	for(i:=0; i < n; i+=channels){
		b[0:] = tickFrame();
		b = b[channels:];
	}
	return buf;
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
