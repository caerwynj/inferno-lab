PAPER: module {
	Article: adt {
		title:	string;
		bodynm:	string;
		videonm:	string;
	};
	scanpaper: fn(s: string): (string, string, list of ref Article);
	getarticle: fn(s: string): string;
};
