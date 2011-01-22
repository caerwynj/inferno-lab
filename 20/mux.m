Muxm: module {
	Muxrpc: adt {
		r: chan of int;
		p: array of byte;
		sleeping: int;
	};

	Mux: adt {
		lk : chan of int;
		ntag: int;
		nsleep: int;
		wait: array of ref Muxrpc;
		muxer: int;
		tagrend: chan of int;

		rpc: fn(mux: self ref Mux, tx: array of byte): array of byte;
		gettag: fn(mux: self ref Mux, r: ref Muxrpc): int;
		puttag: fn(mux: self ref Mux, r: ref Muxrpc, tag: int);
		lock: fn(mux: self ref Mux);
		unlock: fn(mux: self ref Mux);
		send: fn(mux: self ref Mux, p: array of byte): int;
		recv: fn(mux: self ref Mux): array of byte;
	};
	new: fn(): ref Mux;
};

