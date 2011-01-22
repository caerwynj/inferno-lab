all: client server
CFLAGS += -Wall
client: client.c rudp.o
server: server.c rudp.o


.PHONY: clean
clean:
	rm -rf client server *.o

