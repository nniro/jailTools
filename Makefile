#! /bin/sh

BINARY=cryptPass
OBJECTS=cryptPass.o
CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990 -Lusr/local/musl/lib
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=$(MUSLOBJECTS) $(MUSLGCC)
LIBS=-lcrypt $(MUSLOBJECTS)
LDFLAGS=-static
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

ALL: musl/configure $(MUSL) $(BINARY)

musl/configure:
	git submodule init musl
	git submodule update musl

$(MUSL):
	sh ./configMusl.sh
	make -C musl
	make -C musl install

$(BINARY): $(OBJECTS)
	$(GCC) $(CFLAGS) $(LDFLAGS) $(LIBS) $(OBJECTS) -o $(BINARY)

%.o: %.c
	$(GCC) $(CFLAGS) -c $<

clean:
	rm -f $(BINARY) *.o
