implement Midi2skini;

include "sys.m";
	sys:Sys;
	print,fprint,fildes:import sys;
include "draw.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "midi.m";
	midi:Midi;
	Header, Track, Event: import midi;

Midi2skini: module {
	init:fn(nil:ref Draw->Context, args:list of string);
};

tpb :real;
bpm := 120;
tickrate :real;

init(nil:ref Draw->Context, args:list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	midi = load Midi Midi->PATH;
	midi->init(bufio);
	args = tl args;
	io := bufio->open(hd args, Bufio->OREAD);
	if(io == nil)
		exit;
	hdr := midi->read(io);
	tpb = real hdr.tpb;
	interleave(hdr);
}

interleave(hdr: ref Header)
{
	for(;;){
		min := 100000;
		for(i:=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events > 0 && hdr.tracks[i].events[0].delta < min)
				min = hdr.tracks[i].events[0].delta;
		}
		if(min == 100000)
			break;
		l : list of ref Event;
		for(i=0; i< len hdr.tracks; i++){
			if(len hdr.tracks[i].events > 0){
				if(hdr.tracks[i].events[0].delta <= min){
					l = hdr.tracks[i].events[0] :: l;
					hdr.tracks[i].events = hdr.tracks[i].events[1:];
				}else{
					hdr.tracks[i].events[0].delta -= min;
				}
			}
		}
		first := 1;
		for(; l != nil; l = tl l){
			e :=hd l;
			if(first){
				outevent(e);
				first = 0;
			}else{
				e.delta = 0;
				outevent(e);
			}
		}
	}
}

outevent(m: ref Event)
{
	pick e := m {
	Control =>
		case e.etype {
			Midi->NOTEON =>
				realtime := real e.delta /  tickrate;
				ev := "NoteOn";
				if(e.param2 == 0)
					ev = "NoteOff";
				print("%s\t%f\t%d\t%d\t%d\n", ev, realtime, e.mchannel, e.param1, e.param2);
			Midi->NOTEOFF =>
				print("NoteOff\n");
		}
	Sysex =>
		fprint(fildes(2), "sysex\n");
	Meta =>
		if(e.etype == Midi->TEMPO){
			n := 0;
			for(k:=0; k < len e.data; k++)
				n = (n<<8)| int e.data[k];
			bpm = 60000000 / n;
			tickrate =  (real bpm/  60.0) * tpb;
		}
#		else	fprint(fildes(2), "meta %s\n", string e.data);
	}
}
