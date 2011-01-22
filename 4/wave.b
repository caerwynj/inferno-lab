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
rate:=1.0;
time := 0.0;
swab := 0;

init(argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	if(len argv != 1) {
		sys->fprint(sys->fildes(2), "signal expecting filename\n");
		exit;
	}
	data = readfile(hd argv);
	config("pitch 440.0");
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

config(s: string)
{
	(n, flds) := sys->tokenize(s, " \t\n\r");
	case hd flds {
	"pitch" =>
		pitch = real hd tl flds;
		rate = real(len data) * pitch / samplerate;
	}
	configstr = sys->sprint("rate %d\nchans %d\nfreq %g\n", int samplerate, channels, pitch);
}

readfile(file: string): array of real
{
	n := 0;
	y := array[8] of real;
	io := bufio->open(file, bufio->OREAD);
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
