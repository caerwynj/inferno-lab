implement Xp;

include "sys.m";
	sys : Sys;
include "draw.m";
include "bufio.m";
include "edit.m";
	edit: Edit;
include "regx.m";
	regx: Regx;
	Text: import regx;
include "ecmd.m";
	ecmd: Editcmd;

Xp: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

loaderror(s: string)
{
	sys->fprint(sys->fildes(2), "load failed: %s\n", s);
	exit;
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	regx = load Regx Regx->PATH;
	if(regx == nil) loaderror(Regx->PATH);
	ecmd = load Editcmd Editcmd->PATH;
	if(ecmd == nil) loaderror(Editcmd->PATH);
	edit = load Edit Edit->PATH;
	if(edit == nil) loaderror(Edit->PATH);

# these dependencies need to be fixed. edit doesn't really need regx.
# ecmd can call edit. edit does not need know ecmd.
	regx->init();
	edit->init(ecmd);
	ecmd->init(edit, regx);
	args = tl args;
	re := hd args;
	s := hd tl args;
	t := Text.new(s);

	edit->editcmd(t, re, len re);
}
