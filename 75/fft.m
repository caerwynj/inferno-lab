#       fft.zip [1] code written originaly by Don Cross <dcross@intersrv.com>
#		and translated from c to limbo, by Salva Peiró.
#
#       [1] http://groovit.disjunkt.com/analog/time-domain/fft.html

FFT: module{
	PATH:	con	"fft.dis"; # "/dis/math/fft.dis"

	ispow2: fn(x: int): int;
	bitsneeded: fn(pow2: int): int;
	revbits: fn(idx,nbits: int): int;
	ind2freq: fn(n,i: int): real;

	fft_real: fn(ns,inv: int, ri,ii,ro,io: array of real);
};
