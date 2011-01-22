
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

readfile(file: string): array of real
{
	n := 0;
	r : real;
	y := array[8] of real;
	io := bufio->open(file, bufio->OREAD);
	for(;;){
	 	(b, eof) := getw(io);
		if(eof)
			break;
		if(n >= len y)
			y = (array[len y * 2] of real)[0:] = y;
		r = real b;
		y[n++] = r;
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

getw(fd: ref Sys->FD): (real, int)
{
	buf:= array[2] of byte;
	n := sys->read(fd, buf, 2);
	if(n != 2)
		return (0.0, 1);
	if(swab)
		return (real((buf[1]<<24 | buf[0] << 16) >> 16), 0);
	else 
		return (real((buf[0]<<24 | buf[1] << 16) >> 16), 0);
}

normalize(data: array of real, peak: real)
{
	max := 0.0;

	for(i := 0; i < len data; i++)
		if(fabs(data[i])>max)
			max = fabs(data[i]);
	if(max >0.0){
		max = 1.0/max;
		max *= peak;
		for(i = 0; i < len data; i++)
			data [i] *= max;
	}
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

