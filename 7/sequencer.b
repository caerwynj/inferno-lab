implement Sequencer;

include "sys.m";
	sys: Sys;
	fprint, fildes: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "dsp.m";
	dsp: Dsp;
	Sig: import dsp;

midi2pitch:= array[129] of {
8.18,8.66,9.18,9.72,10.30,10.91,11.56,12.25,
12.98,13.75,14.57,15.43,16.35,17.32,18.35,19.45,
20.60,21.83,23.12,24.50,25.96,27.50,29.14,30.87,
32.70,34.65,36.71,38.89,41.20,43.65,46.25,49.00,
51.91,55.00,58.27,61.74,65.41,69.30,73.42,77.78,
82.41,87.31,92.50,98.00,103.83,110.00,116.54,123.47,
130.81,138.59,146.83,155.56,164.81,174.61,185.00,196.00,
207.65,220.00,233.08,246.94,261.63,277.18,293.66,311.13,
329.63,349.23,369.99,392.00,415.30,440.00,466.16,493.88,
523.25,554.37,587.33,622.25,659.26,698.46,739.99,783.99,
830.61,880.00,932.33,987.77,1046.50,1108.73,1174.66,1244.51,
1318.51,1396.91,1479.98,1567.98,1661.22,1760.00,1864.66,1975.53,
2093.00,2217.46,2349.32,2489.02,2637.02,2793.83,2959.96,3135.96,
3322.44,3520.00,3729.31,3951.07,4186.01,4434.92,4698.64,4978.03,
5274.04,5587.65,5919.91,6271.93,6644.88,7040.00,7458.62,7902.13,
8372.02,8869.84,9397.27,9956.06,10548.08,11175.30,11839.82,12543.85,
13289.75};

samplerate := 22050.0;

Sequencer: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

BUFSIZE : con 8192;

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	dsp = load Dsp Dsp->PATH;
	dsp->init();
	argv = tl argv;
	inst := array[4] of ref Sig;
	for(i:=0;i<4;i++)
		inst[i] = Sig.open(hd argv);
	io := bufio->fopen(fildes(0), Bufio->OREAD);
	while((s := io.gets('\n')) != nil) {
		(n, flds) := sys->tokenize(s, " \n\t\r");
		if(n == 0)
			continue;
		else if((hd flds)[0:2] == "//")
			continue;
		t := real hd tl flds;
		t *= samplerate;
		voice := int hd tl tl flds;
		nsamples := int t & 16rFFFE;
		out := array[nsamples] of { * => 0.0};
		for(i = 0; i < 4; i++) {
			b := inst[i].read(nsamples);
			for(j :=0; j < len b; j++)
				out[j] += b[j] * 0.25;
		}
		b := dsp->real2pcm(out);
		sys->write(sys->fildes(1), b, len b);
		if(voice > 4 || voice < 0)
			continue;
		case hd flds {
		"NoteOn" =>
			midi := int hd tl tl tl flds;
			fprint(inst[voice].ctl, "on %g", midi2pitch[midi%len midi2pitch]);
		"NoteOff" =>
			fprint(inst[voice].ctl, "off");
		}
	}
}
