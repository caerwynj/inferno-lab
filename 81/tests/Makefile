CC=/mnt/m/r/dslinux/inferno-os/Linux/386/bin/arm-gcc
LD=/mnt/m/r/dslinux/inferno-os/Linux/386/bin/arm-ld

TARG=evtest maxlloc conlloc
all: $(TARG)
	@echo check $(TARG)
	@file $(TARG)
evtest: evtest.o
maxlloc: maxlloc.o
conlloc: conlloc.o

%: %.o
	$(LD) $(LDFLAGS) $< -o $@

clean:
	$(RM) $(TARG) *.o *.gdb
