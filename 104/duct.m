Duct: module
{
	init:	fn(ctxt: ref Draw->Context, args: list of string);
	uplink: fn(infd: ref Sys->FD, outfd: ref Sys->FD, out: string, in: string);
};
