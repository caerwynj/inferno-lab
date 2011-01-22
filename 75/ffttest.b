implement ffttest;
include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "math.m";
	math: Math;
include "fft.m";
	fft: FFT;

ffttest: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	fft = load FFT FFT->PATH;

	n := 0;
	a:= array[100] of {* => 0.0};
	b:= array[100] of {* => 0.0};
	c:= array[100] of {* => 0.0};
	d:= array[100] of {* => 0.0};
	
	io := bufio->fopen(sys->fildes(0), bufio->OREAD);
	while((t := io.gett(" \n\r\t")) != nil){
		if(n >= len a)
			a = (array[len a + 100] of real)[0:] = a;
		a[n++] = real t;
		#sys->print("n%d s%s g%g\n", n, a[n], b[n]);
	}

#	sys->print("# calc fft (a, b, %d)\n", n);
	fft->fft_real(n, 0, a[0:n], b[0:n], c[0:n], d[0:n]);
#	sys->print("# results: \n");
	for(i:=0; i<n; i++)
		print("%0.3g %0.3g %0.3g %0.3g\n", 
			a[i], b[i], mod(c[i], d[i]), phase(c[i], d[i]));
}

# calc module & phase
mod(a,b: real) : real
{
	return math->sqrt(a*a + b*b);
}
phase(a,b: real) : real
{
	return math->atan2(b, a) * 360.0/(2.0 * math->Pi);
}