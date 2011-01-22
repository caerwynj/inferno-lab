Sequencer: module
{
	PATH: con "sequencer.dis";
	CFREQ, CKEYON, CKEYOFF, CATTACK, CDECAY, CSUSTAIN, 
	CRELEASE, CDELAY, CVOICE, CMIX, CHIGH, CLOW,
	CPOLE, CZERO, CRADIUS, CTUNE: con iota;

	BLOCK : con 4490;

	Inst: adt {
		c: Sample;
		ctl: Control;

		mk: fn(insts: Source, f: Instrument): ref Inst;
	};

	Source: type array of ref Inst;
	Sample: type chan of (array of real, chan of array of real);
	Control: type chan of (int, real);
	Instrument: type ref fn(s: Source, c: Sample, ctl: Control);

	init: fn(nil: ref Draw->Context, argv: list of string);
	modinit: fn();
	play: fn(file: string, ctl: chan of string, inst: ref Inst);

	fm: fn(s: Source, c: Sample, ctl: Control);
	master: fn(s: Source, c: Sample, ctl: Control);
	poly: fn(s: Source, c: Sample, ctl: Control);
	lfo: fn(s: Source, c: Sample, ctl: Control);
	delay: fn(s: Source, c: Sample, ctl: Control);
	onepole: fn(s: Source, c: Sample, ctl: Control);
	onezero: fn(s: Source, c: Sample, ctl: Control);
	twopole: fn(s: Source, c: Sample, ctl: Control);
	twozero: fn(s: Source, c: Sample, ctl: Control);
	mixer: fn(s: Source, c: Sample, ctl: Control);
	waveloop: fn(s: Source, c: Sample, ctl: Control);
	adsr: fn(s: Source, c: Sample, ctl: Control);

	sinewave: fn(): array of real;
	halfwave: fn(): array of real;
	sineblnk: fn(): array of real;
	fwavblnk: fn(): array of real;
	noise: fn(): array of real;
	impuls: fn(n: int): array of real;

	norm2raw: fn(v: array of real): array of byte;
};
