implement Command;
include "cmd.m";
include "turtle.m";
turtle: Turtle;
Triple: import turtle;

main(argv: list of string)
{
	argv = tl argv;

	if (len argv == 0) raise "args: t1 file";
	file := hd argv;

	turtle = load Turtle Turtle->PATH;
	if (turtle == nil) raise "load turtle";
	turtle->init();
	triples := turtle->read(file);
	for (l := triples; l != nil; l = tl l) {
		t := hd l;
		print("%s %s %s\n", t.s, t.p, t.o);
	}
}
