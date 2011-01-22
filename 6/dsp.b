implement Dsp;

include "dsp.m";

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
