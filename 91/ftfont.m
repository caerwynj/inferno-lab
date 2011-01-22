Ftfont: module {
	PATH: con "ftfont.dis";
	Font: adt
	{
		name:	string;		# *default* or a file name (this may change)
		height:	int;		# interline spacing of font
		ascent:	int;		# distance from baseline to top
		display:	ref Draw->Display;	# where Font resides
		face:		ref Freetype->Face;

		# read from file or construct from local description
		open:		fn(d: ref Draw->Display, name: string, size: int): ref Font;
		build:		fn(d: ref Draw->Display, name, desc: string): ref Font;
		# string extents
		width:		fn(f: self ref Font, str: string): int;
		bbox:		fn(f: self ref Font, str: string): Draw->Rect;
		stringx:		fn(f: self ref Font, d : ref Draw->Image, p : Draw->Point, s : string, c : ref Draw->Image);
	};
};

