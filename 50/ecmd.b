implement Editcmd;

include "sys.m";
	sys : Sys;
	sprint: import sys;
include "draw.m";
include "bufio.m";
include "edit.m";
	edit: Edit;
	aNo, aDot, aAll, C_nl, C_a,  C_c, C_g, 
	C_i, C_p, C_s, C_x, 
	C_pipe, C_eq, Addr, Address, String, Cmd: import Edit;
	cmdtab, curtext, newaddr, cmdlookup, editerror: import edit;
include "regx.m";
	regx: Regx;
	FALSE, TRUE, NRange, Range, Rangeset, Text,
	rxcompile, rxexecute, rxbexecute: import regx;
include "sh.m";
	sh: Sh;
	Context, Listnode: import sh;

include "ecmd.m";

nest: int;

addr: Address;
sel: Rangeset;

init(e: Edit, r: Regx)
{
	sys = load Sys Sys->PATH;
	sh  = load Sh Sh->PATH;
	edit = e;
	regx = r;
}

cmdtabexec(i: int, t: ref Text, cp: ref Cmd): int
{
	case (cmdtab[i].fnc){
		C_nl	=> i = nl_cmd(t, cp);
		C_a 	=> i = a_cmd(t, cp);
		C_c	=> i = c_cmd(t, cp);
		C_g	=> i = g_cmd(t, cp);
		C_i	=> i = i_cmd(t, cp);
		C_p	=> i = p_cmd(t, cp);
		C_s	=> i = s_cmd(t, cp);
		C_x	=> i = x_cmd(t, cp);
		C_eq => i = eq_cmd(t, cp);
		C_pipe	=> i = pipe_cmd(t, cp);
		* =>	editerror("bad case in cmdtabexec");
	}
	return i;
}

cmdexec(t: ref Text, cp: ref Cmd): int
{
	i: int;
	ap: ref Addr;
	dot: Address;

	i = cmdlookup(cp.cmdc);	# will be -1 for '{' 
	if(i>=0 && cmdtab[i].defaddr != aNo){
		if((ap=cp.addr)==nil && cp.cmdc!='\n'){
			cp.addr = ap = newaddr();
			ap.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.typex = '*';
		}else if(ap!=nil && ap.typex=='"' && ap.next==nil && cp.cmdc!='\n'){
			ap.next = newaddr();
			ap.next.typex = '.';
			if(cmdtab[i].defaddr == aAll)
				ap.next.typex = '*';
		}
		if(cp.addr!=nil){	# may be false for '\n' (only)
			if(t!=nil){
				dot = mkaddr(t);
				addr = cmdaddress(ap, dot, 0);
			}else	# a "
				addr = cmdaddress(ap, none, 0);
		}
	}
	case(cp.cmdc){
	'{' =>
		dot = mkaddr(t);
		if(cp.addr != nil)
			dot = cmdaddress(cp.addr, dot, 0);
		for(cp = cp.cmd; cp!=nil; cp = cp.next){
			t.q0 = dot.r.q0;
			t.q1 = dot.r.q1;
			cmdexec(t, cp);
		}
		break;
	* =>
		if(i < 0)
			editerror(sprint("unknown command %c in cmdexec", cp.cmdc));
		i = cmdtabexec(i, t, cp);
		return i;
	}
	return 1;
}

x_cmd(t: ref Text, cp: ref Cmd): int
{
	if(cp.re!=nil)
		looper(t, cp, cp.cmdc=='x');
	else
		linelooper(t, cp);
	return TRUE;
}

looper(t: ref Text, cp: ref Cmd, xy: int)
{
	p, op, nrp, ok: int;
	r, tr: Range;
	rp: array of  Range;

	r = addr.r;
	if(xy)
		op = -1;
	else
		op = r.q0;
	nest++;
	if(rxcompile(cp.re.r) == FALSE)
		editerror(sprint("bad regexp in %c command", cp.cmdc));
	nrp = 0;
	rp = nil;
	for(p = r.q0; p<=r.q1; ){
		(ok, sel) = rxexecute(t, nil, p, r.q1);
		if(!ok){ # no match, but y should still run
			if(xy || op>r.q1)
				break;
			tr.q0 = op;
			tr.q1 = r.q1;
			p = r.q1+1;	# exit next loop
		}else{
			if(sel[0].q0==sel[0].q1){	# empty match?
				if(sel[0].q0==op){
					p++;
					continue;
				}
				p = sel[0].q1+1;
			}else
				p = sel[0].q1;
			if(xy)
				tr = sel[0];
			else{
				tr.q0 = op;
				tr.q1 = sel[0].q0;
			}
		}
		op = sel[0].q1;
		nrp++;
		orp := rp;
		rp = array[nrp] of Range;
		rp[0: ] = orp[0: nrp-1];
		rp[nrp-1] = tr;
		orp = nil;
	}
	loopcmd(t, cp.cmd, rp, nrp);
	rp = nil;
	--nest;
}

linelooper(f: ref Text, cp: ref Cmd)
{
	nrp, p: int;
	r, linesel: Range;
	a, a3: Address;
	rp: array of Range;

	nest++;
	nrp = 0;
	rp = nil;
	r = addr.r;
	a3.f = f;
	a3.r.q0 = a3.r.q1 = r.q0;
	a = lineaddr(0, a3, 1);
	linesel = a.r;
	for(p = r.q0; p<r.q1; p = a3.r.q1){
		a3.r.q0 = a3.r.q1;
		if(p!=r.q0 || linesel.q1==p){
			a = lineaddr(1, a3, 1);
			linesel = a.r;
		}
		if(linesel.q0 >= r.q1)
			break;
		if(linesel.q1 >= r.q1)
			linesel.q1 = r.q1;
		if(linesel.q1 > linesel.q0)
			if(linesel.q0>=a3.r.q1 && linesel.q1>a3.r.q1){
				a3.r = linesel;
				nrp++;
				orp := rp;
				rp = array[nrp] of Range;
				rp[0: ] = orp[0: nrp-1];
				rp[nrp-1] = linesel;
				orp = nil;
				continue;
			}
		break;
	}
	loopcmd(f, cp.cmd, rp, nrp);
	rp = nil;
	--nest;
}

loopcmd(t: ref Text, cp: ref Cmd, rp: array of Range, nrp: int)
{
	i: int;

	for(i=0; i<nrp; i++){
		t.q0 = rp[i].q0;
		t.q1 = rp[i].q1;
		cmdexec(t, cp);
	}
}

lineaddr(l: int, addr: Address, sign: int): Address
{
	n: int;
	c: int;
	f := addr.f;
	a: Address;
	p: int;

	a.f = f;
	curtext = addr.f;
	if(sign >= 0){
		if(l == 0){
			if(sign==0 || addr.r.q1==0){
				a.r.q0 = a.r.q1 = 0;
				return a;
			}
			a.r.q0 = addr.r.q1;
			p = addr.r.q1-1;
		}else{
			if(sign==0 || addr.r.q1==0){
				p = 0;
				n = 1;
			}else{
				p = addr.r.q1-1;
				n = curtext.readc(p++)=='\n';
			}
			while(n < l){
				if(p >= f.nc)
					editerror("address out of range");
				if(curtext.readc(p++) == '\n')
					n++;
			}
			a.r.q0 = p;
		}
		while(p < curtext.nc && curtext.readc(p++)!='\n')
			;
		a.r.q1 = p;
	}else{
		p = addr.r.q0;
		if(l == 0)
			a.r.q1 = addr.r.q0;
		else{
			for(n = 0; n<l; ){	# always runs once
				if(p == 0){
					if(++n != l)
						editerror("address out of range");
				}else{
					c = curtext.readc(p-1);
					if(c != '\n' || ++n != l)
						p--;
				}
			}
			a.r.q1 = p;
			if(p > 0)
				p--;
		}
		while(p > 0 && curtext.readc(p-1)!='\n')	# lines start after a newline
			p--;
		a.r.q0 = p;
	}
	return a;
}

g_cmd(t: ref Text, cp: ref Cmd): int
{
	ok: int;

	if(rxcompile(cp.re.r) == FALSE)
		editerror("bad regexp in g command");
	(ok, sel) = rxexecute(t, nil, addr.r.q0, addr.r.q1);
	if(ok ^ cp.cmdc=='v'){
		t.q0 = addr.r.q0;
		t.q1 = addr.r.q1;
		return cmdexec(t, cp.cmd);
	}
	return TRUE;
}

mkaddr(f: ref Text): Address
{
	a: Address;

	a.r.q0 = f.q0;
	a.r.q1 = f.q1;
	a.f = f;
	return a;
}

none: Address;

charaddr(l: int, addr: Address, sign: int): Address
{
	if(sign == 0)
		addr.r.q0 = addr.r.q1 = l;
	else if(sign < 0)
		addr.r.q1 = addr.r.q0 -= l;
	else if(sign > 0)
		addr.r.q0 = addr.r.q1 += l;
	if(addr.r.q0<0 || addr.r.q1>addr.f.nc)
		editerror("address out of range");
	return addr;
}

nextmatch(f: ref Text, r: ref String, p: int, sign: int)
{
	ok: int;

	if(rxcompile(r.r) == FALSE)
		editerror("bad regexp in command address");
	if(sign >= 0){
		(ok, sel) = rxexecute(f, nil, p, 16r7FFFFFFF);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q0==p){
			if(++p>f.nc)
				p = 0;
			(ok, sel) = rxexecute(f, nil, p, 16r7FFFFFFF);
			if(!ok)
				editerror("address");
		}
	}else{
		(ok, sel) = rxbexecute(f, p);
		if(!ok)
			editerror("no match for regexp");
		if(sel[0].q0==sel[0].q1 && sel[0].q1==p){
			if(--p<0)
				p = f.nc;
			(ok, sel) = rxbexecute(f, p);
			if(!ok)
				editerror("address");
		}
	}
}


nl_cmd(t: ref Text, cp: ref Cmd): int
{
	a: Address;

	if(cp.addr == nil){
		# First put it on newline boundaries
		a = mkaddr(t);
		addr = lineaddr(0, a, -1);
		a = lineaddr(0, a, 1);
		addr.r.q1 = a.r.q1;
		if(addr.r.q0==t.q0 && addr.r.q1==t.q1){
			a = mkaddr(t);
			addr = lineaddr(1, a, 1);
		}
	}
#	t.show(addr.r.q0, addr.r.q1);
	return TRUE;
}

cmdaddress(ap: ref Addr, a: Address, sign: int): Address
{
	f := a.f;
	a1, a2: Address;

	do{
		case(ap.typex){
		'l' or
		'#' =>
			if(ap.typex == '#')
				a = charaddr(ap.num, a, sign);
			else
				a = lineaddr(ap.num, a, sign);
			break;

		'.' =>
			a = mkaddr(f);
			break;

		'$' =>
			a.r.q0 = a.r.q1 = f.nc;
			break;

		'\'' =>
editerror("can't handle '");
#			a.r = f.mark;
			break;

		'?' =>
			sign = -sign;
			if(sign == 0)
				sign = -1;
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'/' =>
			if(sign >= 0)
				v := a.r.q1;
			else
				v = a.r.q0;
			nextmatch(f, ap.re, v, sign);
			a.r = sel[0];
			break;

		'"' =>
#			f = matchfile(ap.re);
			a = mkaddr(f);
			break;

		'*' =>
			a.r.q0 = 0;
			a.r.q1 = f.nc;
			return a;

		',' or
		';' =>
			if(ap.left!=nil)
				a1 = cmdaddress(ap.left, a, 0);
			else{
				a1.f = a.f;
				a1.r.q0 = a1.r.q1 = 0;
			}
			if(ap.typex == ';'){
				f = a1.f;
				a = a1;
				f.q0 = a1.r.q0;
				f.q1 = a1.r.q1;
			}
			if(ap.next!=nil)
				a2 = cmdaddress(ap.next, a, 0);
			else{
				a2.f = a.f;
				a2.r.q0 = a2.r.q1 = f.nc;
			}
			if(a1.f != a2.f)
				editerror("addresses in different files");
			a.f = a1.f;
			a.r.q0 = a1.r.q0;
			a.r.q1 = a2.r.q1;
			if(a.r.q1 < a.r.q0)
				editerror("addresses out of order");
			return a;

		'+' or
		'-' =>
			sign = 1;
			if(ap.typex == '-')
				sign = -1;
			if(ap.next==nil || ap.next.typex=='+' || ap.next.typex=='-')
				a = lineaddr(1, a, sign);
			break;
		* =>
			editerror("cmdaddress");
			return a;
		}
	}while((ap = ap.next)!=nil);	# assign =
	return a;
}

p_cmd(t: ref Text, nil: ref Cmd): int
{
	sys->print("%s", dottext(t));
	return TRUE;
}

dottext(t: ref Text): string
{
	buf :string;
	n := 0;
	q0 := t.q0;
	while(q0 < t.q1){
		buf[n++] = t.readc(q0);
		q0++;
	}
	return string buf;
}

pipe_cmd(t: ref Text, cp: ref Cmd): int
{
#	runpipe(t, cp.cmdc, cp.text.r, cp.text.n, 0);
	sync := chan of int;
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return FALSE;
	ctxt := Context.new(nil);
	spawn exec(ctxt, sync, cp.text.r, p[1]);
	<-sync;
	p[1] = nil;
	buf := array of byte dottext(t);
	sys->write(p[0], buf, len buf);
	p[0] = nil;
	<-sync;
	return TRUE;
}

exec(ctxt: ref Context, sync: chan of int, cmd : string, stdin: ref Sys->FD)
{
	pid := sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sys->pctl(Sys->NEWFD, 0 :: 1 :: 2 :: nil);
	ctxt = ctxt.copy(0);
	sync <-= pid;
	ctxt.run(ref Listnode(nil, cmd) :: nil, 0);
	sys->pctl(Sys->NEWFD, nil);
	ctxt = nil;
	sync <-= 0;
}

nlcount(t: ref Text, q0: int, q1: int): int
{
	nl: int;
	nl = 0;
	while(q0 < q1){
		if(t.readc(q0) == '\n')
			nl++;
		q0++;
	}
	return nl;
}

printposn(t: ref Text, charsonly: int)
{
	l1, l2: int;

	if(t != nil &&  t.name != nil)
		sys->print("%s:", t.name);
	if(!charsonly){
		l1 = 1+nlcount(t, 0, addr.r.q0);
		l2 = l1+nlcount(t, addr.r.q0, addr.r.q1);
		# check if addr ends with '\n' 
		if(addr.r.q1>0 && addr.r.q1>addr.r.q0 && t.readc(addr.r.q1-1)=='\n')
			--l2;
		sys->print("%ud", l1);
		if(l2 != l1)
			sys->print(",%ud", l2);
		sys->print("\n");
		return;
	}
	sys->print("#%d", addr.r.q0);
	if(addr.r.q1 != addr.r.q0)
		sys->print(",#%d", addr.r.q1);
	sys->print("\n");
}

eq_cmd(t: ref Text, cp: ref Cmd): int
{
	charsonly: int;

	case(cp.text.n){
	0 =>
		charsonly = FALSE;
		break;
	1 =>
		if(cp.text.r[0] == '#'){
			charsonly = TRUE;
			break;
		}
	* =>
		charsonly = TRUE;
		editerror("newline expected");
	}
	printposn(t, charsonly);
	return TRUE;
}

a_cmd(t: ref Text, cp: ref Cmd): int
{
	sys->print("%s%s", dottext(t), cp.text.r);
	return TRUE;
}

i_cmd(t: ref Text, cp: ref Cmd): int
{
	sys->print("%s%s", cp.text.r, dottext(t));
	return TRUE;
}

c_cmd(nil: ref Text, cp: ref Cmd): int
{
	sys->print("%s", cp.text.r);
	return TRUE;
}

s_cmd(t: ref Text, cp: ref Cmd): int
{
	i, j, k, c, m, n, nrp, didsub, ok: int;
	p1, op, delta: int;
	buf: string;
	rp: array of Rangeset;

	n = cp.num;
	op= -1;
	if(rxcompile(cp.re.r) == FALSE)
		editerror("bad regexp in s command");
	nrp = 0;
	rp = nil;
	delta = 0;
	didsub = FALSE;
	for(p1 = addr.r.q0; p1<=addr.r.q1; ){
		(ok, sel) = rxexecute(t, nil, p1, addr.r.q1);
		if(!ok)
			break;
		if(sel[0].q0 == sel[0].q1){	# empty match?
			if(sel[0].q0 == op){
				p1++;
				continue;
			}
			p1 = sel[0].q1+1;
		}else
			p1 = sel[0].q1;
		op = sel[0].q1;
		if(--n>0)
			continue;
		nrp++;
		orp := rp;
		rp = array[nrp] of Rangeset;
		rp[0: ] = orp[0:nrp-1];
		rp[nrp-1] = copysel(sel);
		orp = nil;
	}
	for(m=0; m<nrp; m++){
		sel = rp[m];
		for(i = 0; i<cp.text.n; i++)
			if((c = cp.text.r[i])=='\\' && i<cp.text.n-1){
				c = cp.text.r[++i];
				if('1'<=c && c<='9') {
					j = c-'0';
					for(k=sel[j].q0; k<sel[j].q1; k++)
						buf[len buf] = t.readc(k);
				}else
				 	buf[len buf] = c;
			}else if(c!='&')
				 buf[len buf] = c;
			else{
				for(k=sel[0].q0; k<sel[0].q1; k++)
					buf[len buf] = t.readc(k);
			}
		sys->print("%s", buf);
		delta -= sel[0].q1-sel[0].q0;
		delta += len buf;
		didsub = 1;
		if(!cp.flag)
			break;
	}
	rp = nil;
	if(!didsub && nest==0)
		editerror("no substitution");
	t.q0 = addr.r.q0;
	t.q1 = addr.r.q1+delta;
	return TRUE;
}

copysel(rs: Rangeset): Rangeset
{
	nrs := array[NRange] of Range;
	for(i := 0; i < NRange; i++)
		nrs[i] = rs[i];
	return nrs;
}
