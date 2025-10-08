TARG=\
	turtle.dis\
	t1.dis\
	t2.dis\
	y.tab.dis\
	query.dis\
	triplestore.dis\

MODULES=\
	query.m\
	turtle.m\
	triplestore.m\


DISBIN=$ROOT/dis

%.dis: %.b
	limbo -gw $stem.b

all:V: $TARG

install:
	cp query.dis turtle.dis $DISBIN/lib
	cp y.tab.dis $DISBIN/sparql.dis
	cp query.m turtle.m $ROOT/module

clean:V:
	rm -f *.dis *.sbl

y.tab.b: sparql.y
	mash yacc sparql.y

%.dis:	$MODULES
