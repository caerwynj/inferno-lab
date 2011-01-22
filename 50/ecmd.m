Editcmd: module {

	PATH: con "ecmd.dis";

	init : fn(e: Edit, r: Regx);
	cmdexec: fn(a0: ref Regx->Text, a1: ref Edit->Cmd): int;
};