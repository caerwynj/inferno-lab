implement Reader;

include "sys.m";
include "mapred.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;

map: Mapper;
emit: chan of (string, string);

init(m: Mapper, e: chan of (string, string))
{
	map = m;
	emit = e;
	bufio = load Bufio Bufio->PATH;
}

read(file: string, offset: big, nbytes: big)
{
	io := bufio->open(file, Sys->OREAD);
	while((s := io.gets('\n')) != nil){
		map->map(file, s, emit);
	}
}
