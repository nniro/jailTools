#! /bin/bash

BINARY=cryptPass
OBJECTS=cryptPass.o
CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990 -L/usr/local/musl/lib
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=$(MUSLOBJECTS) $(MUSLGCC)
LIBS=-lcrypt $(MUSLOBJECTS)
LDFLAGS=
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

ALL: $(MUSL) $(BINARY)

$(MUSL):
	bash ./configMusl.sh
	make -C musl
	make -C musl install

$(BINARY): $(OBJECTS)
	$(GCC) $(CFLAGS) $(LDFLAGS) $(LIBS) $(OBJECTS) -o $(BINARY)

%.o: %.c
	$(GCC) $(CFLAGS) -c $<

clean:
	rm -f $(BINARY) *.o
