#! /bin/sh

BINARY=cryptPass
OBJECTS=cryptPass.o
CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990 -Lusr/local/musl/lib
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=$(MUSLOBJECTS) $(MUSLGCC)
BUSYBOX=busybox/busybox
LIBS=-lcrypt $(MUSLOBJECTS)
LDFLAGS=-static
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

ALL: busybox/configure $(BUSYBOX) $(BINARY)

musl/configure:
	git submodule init musl
	git submodule update musl

busybox/configure: musl/configure $(MUSL)
	git submodule init busybox
	git submodule update busybox
	ln -sf /usr/include/linux usr/include/
	ln -sf /usr/include/asm usr/include/
	ln -sf /usr/include/asm-generic usr/include/

$(MUSL):
	sh ./configMusl.sh
	make -C musl
	make -C musl install

$(BUSYBOX): $(MUSL)
	cp busybox.config busybox/.config
	make CC=$(PROJECTROOT)/$(GCC) -C busybox

$(BINARY): $(OBJECTS)
	$(GCC) $(CFLAGS) $(LDFLAGS) $(LIBS) $(OBJECTS) -o $(BINARY)

%.o: %.c
	$(GCC) $(CFLAGS) -c $<

clean:
	rm -f $(BINARY) *.o
