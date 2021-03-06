implement Ir;

include "sys.m";
include "keyboard.m";
sys: Sys;
FD: import sys;

include "ir.m";

rawon: ref FD;

init(keys, pid: chan of int): int
{
	dfd: ref FD;

	sys = load Sys Sys->PATH;

	dfd = sys->open("/dev/keyboard", sys->OREAD);
	if(dfd == nil)
		return -1;

	spawn reader(keys, pid, dfd);
	return 0;
}

reader(keys, pid: chan of int, dfd: ref FD)
{
	n: int;

	nb := 0;
	b:= array[1] of byte;
	buf := array[10] of byte;
	pid <-= sys->pctl(0,nil);
	for(;;) {
		n = sys->read(dfd, b, 1);
		if(n != 1)
			break;
		if(nb>= len buf){
			sys->print("irsim: confused by input\n");
			break;
		}

		buf[nb++] = b[0];
		nutf := sys->utfbytes(buf, nb);
		if(nutf > 0){
			s := string buf[0:nutf];
			keys <-= s[0];
			nb = 0;
		}
	}
	keys <-= Ir->EOF;
}

translate(key: int): int
{
	n := Ir->Error;

	case key {
	'0' =>	n = Ir->Zero;
	'1' =>	n = Ir->One;
	'2' =>	n = Ir->Two;
	'3' =>	n = Ir->Three;
	'4' =>	n = Ir->Four;
	'5' =>	n = Ir->Five;
	'6' =>	n = Ir->Six;
	'7' =>	n = Ir->Seven;
	'8' =>	n = Ir->Eight;
	'9' =>	n = Ir->Nine;
	Keyboard->Pgup =>	n = Ir->ChanUP;		#Xbtn
	Keyboard->Pgdown =>	n = Ir->ChanDN;		#Ybtn
	't' =>	n = Ir->VolUP;			#Lbtn
	'v' =>	n = Ir->VolDN;			#Rbtn
	Keyboard->Right =>	n = Ir->FF;			#Rightbtn
	Keyboard->Left =>	n = Ir->Rew;			#Leftbtn
	Keyboard->Up =>	n = Ir->Up;			#Upbtn
	Keyboard->Down =>	n = Ir->Dn;			#Downbtn
	'\t' =>	n = Ir->Rcl;			#Bbtn
	'\n' =>	n = Ir->Select;			#Abtn
	'\b' =>	n = Ir->Enter;			#Selbtn
	16r7f =>	n = Ir->Power;
	}

	return n;
}
