News: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
	Paper: adt
	{
		title:		string;
		date:		string;
		file:		string;
		menuname:	string;
		menuicon:	ref Image;
		fullname:	string;
		fullicon:	ref Image;
		headfontname:	string;
		headfont:	ref Font;
		textfontname:	string;
		textfont:	ref Font;
		modname:	string;
	};
};
