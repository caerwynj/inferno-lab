implement Command;
include "cmd.m";
include "turtle.m";
include "sqlite.m";

turtle: Turtle;
Triple: import turtle;
sqlite: Sqlite;
Conn, Stmt: import sqlite;

main(argv: list of string)
{
	argv = tl argv;
	rc: int;
	db: ref Conn;
	stmt: ref Stmt;

	sqlite = load Sqlite Sqlite->PATH;
	if(sqlite == nil) {
		print("opening sqlite\n");
		raise "sqlite not loaded\n";
	}

	if (len argv == 0) raise "args: t1 file";
	file := hd argv;

	turtle = load Turtle Turtle->PATH;
	if (turtle == nil) raise "load turtle";
	turtle->init();
	triples := turtle->read(file);

	print("opening db\n");
	(db, rc) = sqlite->open("t1.db");
	if(rc){
		print("error opening db %d\n", rc);
		raise "error opening db";
	}

	(stmt, rc) = sqlite->prepare(db, "insert into triple values (?1, ?2, ?3)");
	if(rc){
		print("error preparing stmt %d\n", rc);
		raise "error preparing stmt";
	}

	for (l := triples; l != nil; l = tl l) {
		t := hd l;
		sqlite->bind_text(stmt, 1, t.s);
		sqlite->bind_text(stmt, 2, t.p);
		sqlite->bind_text(stmt, 3, t.o);
		rc = sqlite->step(stmt);
		if(rc != sqlite->DONE) {
			print("error %d\n", rc);
		 	raise "error executing stmt";
		}
		rc = sqlite->reset(stmt);
		if(rc) print("reset error %d\n", rc);
	}

	rc = sqlite->finalize(stmt);
	print("finalize stmt rc %d\n", rc);
	rc = sqlite->close(db);
	print("close database rc %d\n", rc);
}
