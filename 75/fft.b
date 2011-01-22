implement FFT;
include "sys.m";
	sys: Sys;
	print: import sys;
include "math.m";
	math: Math;
	cos, sin, Degree: import math;
include "fft.m";

# misc
ispow2(x: int): int
{
    if ( x < 2 )
        return 1;

    if ( x & (x-1) )
        return 0;

    return 1;
}

bitsneeded(pow2: int): int
{
    i: int ;

    if (pow2 < 2){
        sys->print ("Error: bitsneeded %d is too small.\n", pow2);
       exit;
    }

    for ( i=0; ; i++ ){
        if (pow2 & (1 << i))
            return i;
    }
}

revbits(idx,nbits: int): int
{
    i, rev: int;

    for (i=rev=0; i < nbits; i++){
        rev = (rev << 1) | (idx & 1);
        idx >>= 1;
    }
    return rev;
}
	
ind2freq(n,i: int): real
{
    if ( i >= n )
        return 0.0;
    else if ( i <= n/2 )
        return real i / real n;

    return - real (n-i) / real n;
}


fft_real(ns,inv: int, ri,ii,ro,io: array of real)
{
    nbits: int;    # Number of bits needed to store indices
    i,j,k,n: int;
    bsize,bend: int;

    anum: real = 2.0 * Math->Pi;
    tr, ti: real;     # temp real, temp imaginary
	if (math == nil){
		sys = load Sys Sys->PATH;
		math = load Math Math->PATH;
	}

    if (!ispow2(ns)){
        sys->print("Error in fft():  ns=%d is not power of two\n", ns);
        exit;
    }

    if (inv)
        anum = -anum;

#    CHECKPOINTER ( ri );
#    CHECKPOINTER ( ro );
#    CHECKPOINTER ( io );

    nbits = bitsneeded (ns);

    # Do simultaneous data copy and bit-reversal ordering into outputs...

    for ( i=0; i < ns; i++ ){
        j = revbits(i, nbits);
        ro[j] = ri[i];
        if (ii == nil)
        	io[j] = 0.0;
        else
        	io[j] = ii[i];
    }

    # Do the FFT itself...

    bend = 1;
    for (bsize = 2; bsize <= ns; bsize <<= 1){
        delta: real = anum / real bsize;
        sm2: real = sin ( -2.0 * delta);
        sm1: real = sin ( -delta);
        cm2: real = cos ( -2.0 * delta);
        cm1: real = cos ( -delta);
        w: real = 2.0 * cm1;
        ar:= array[3] of real;
        ai:= array[3] of real;
#       temp: real;

        for (i=0; i < ns; i += bsize ){
            ar[2] = cm2;
            ar[1] = cm1;

            ai[2] = sm2;
            ai[1] = sm1;
		
			n=0; 
            for (j=i; n < bend; j++){
                ar[0] = w*ar[1] - ar[2];
                ar[2] = ar[1];
                ar[1] = ar[0];

                ai[0] = w*ai[1] - ai[2];
                ai[2] = ai[1];
                ai[1] = ai[0];

                k = j + bend;
                tr = ar[0]*ro[k] - ai[0]*io[k];
                ti = ar[0]*io[k] + ai[0]*ro[k];

                ro[k] = ro[j] - tr;
                io[k] = io[j] - ti;

                ro[j] += tr;
                io[j] += ti;
                n++;
            }
        }

        bend = bsize;
    }

    # Need to normalize if inverse transform...

    if (inv)
    {
        denom:= real ns;

        for (i=0; i < n; i++){
            ro[i] /= denom;
            io[i] /= denom;
        }
    }
}
