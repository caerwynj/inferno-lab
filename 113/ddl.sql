CREATE TABLE triple (
	s text,
	p text,
	o text
);

CREATE INDEX sidx ON triple(s);
CREATE INDEX pidx ON triple(p);
CREATE INDEX oidx ON triple(o);
