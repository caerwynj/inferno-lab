Img: module {
	PATH : con "img.dis";

	Mimerror, Mimnone, Mimpartial, Mimdone: con iota + 1;
	# Media types (must track mnames in chutils.b)
	ApplMsword, ApplOctets, ApplPdf, ApplPostscript, ApplRtf,
	ApplFramemaker, ApplMsexcel, ApplMspowerpoint, 
	UnknownType,

	Audio32kadpcm, AudioBasic,

	ImageCgm, ImageG3fax, ImageGif, ImageIef, ImageJpeg, ImagePng, ImageTiff,
	ImageXBit, ImageXBit2, ImageXBitmulti, ImageXInfernoBit, ImageXXBitmap,

	ModelVrml,

	MultiDigest, MultiMixed,

	TextCss, TextEnriched, TextHtml, TextJavascript, TextPlain, TextRichtext,
	TextSgml, TextTabSeparatedValues, TextXml,

	VideoMpeg, VideoQuicktime : con iota;

	ByteSource: adt 
	{
		data: array of byte;
		eof: int;
		mtype: int;
		lim: int;
		edata: int;
	};
	MaskedImage: adt {
		im:		ref Draw->Image;		# the image
		mask:	ref Draw->Image;		# if non-nil, a mask for the image
		delay:	int;			# if animated, delay in millisec before next frame
		more:	int;			# true if more frames follow
		bgcolor:	int;			# if not -1, restore to this (RGB) color before next frame
		origin:	Draw->Point;		# origin of im relative to first frame of an animation
	};
	# Getmim returns image and possible mask;
	# the int returned is either Mimnone, Mimpartial or Mimdone, depending on
	# how much of returned mim is filled in.
	# if the image is animated, successive calls to getmim return subsequent frames.
	# Errors are indicated by returning Mimerror, with the err field non empty.
	# Should call free() when don't intend to call getmim any more
	ImageSource: adt
	{
		width:	int;
		height:	int;
		origw:	int;
		origh:	int;
		mtype:	int;
		i:		int;
		curframe:	int;
		bs:		ref ByteSource;
		gstate:	ref Gifstate;
		jstate:	ref Jpegstate;
		err:		string;

		new: fn(bs: ref ByteSource, w, h: int) : ref ImageSource;
		getmim: fn(is: self ref ImageSource) : (int, ref MaskedImage);
		free: fn(is: self ref ImageSource);
	};

	# Following are private to implementation
	Jpegstate: adt
	{
		# variables in i/o routines
		sr:	int;	# shift register, right aligned
		cnt:	int;	# # bits in right part of sr
	
		Nf:		int;
		comp:	array of Framecomp;
		mode:	byte;
		X,Y:		int;
		qt:		array of array of int;	# quantization tables
		dcht:		array of ref Huffman;
		acht:		array of ref Huffman;
		Ns:		int;
		scomp:	array of Scancomp;
		Ss:		int;
		Se:		int;
		Ah:		int;
		Al:		int;
		ri:		int;
		nseg:	int;
		nblock:	array of int;
	
		# progressive scan
		dccoeff:	array of array of int;
		accoeff:	array of array of array of int;	# only need 8 bits plus quantization
		nacross:	int;
		ndown:	int;
		Hmax:	int;
		Vmax:	int;
	};

	Huffman: adt
	{
		bits:	array of int;
		size:	array of int;
		code:	array of int;
		val:	array of int;
		mincode:	array of int;
		maxcode:	array of int;
		valptr:	array of int;
		# fast lookup
		value:	array of int;
		shift:	array of int;
	};
	
	Framecomp: adt	# Frame component specifier from SOF marker
	{
		C:	int;
		H:	int;
		V:	int;
		Tq:	int;
	};

	Scancomp: adt	# Frame component specifier from SOF marker
	{
		C:	int;
		tdc:	int;
		tac:	int;
	};

	Gifstate: adt
	{
		fields: int;
		bgrnd: int;
		aspect: int;
		flags: int;
		delay: int;
		trindex: byte;
		tbl: array of GifEntry;
		globalcmap: array of byte;
		cmap: array of byte;
	};

	GifEntry: adt
	{
		prefix: int;
		exten: int;
	};

	init: fn(ctxt: ref Draw->Context);
	supported: fn(mtype: int) : int;
	closest_rgbpix: fn(r, g, b: int) : int;
};
