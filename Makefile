#! /bin/sh

CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=$(MUSLOBJECTS) $(MUSLGCC)
BUSYBOX=busybox/busybox
LIBS=-lcrypt $(MUSLOBJECTS)
LDFLAGS=-static
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

ALL: busybox/configure $(BUSYBOX)

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
	sh -c 'cd buildMusl; sh ./configMusl.sh $(PWD)'
	make -C buildMusl && make -C buildMusl install

$(BUSYBOX): $(MUSL)
	cp busybox.config busybox/.config
	sed -e 's@ gcc@ $(PROJECTROOT)/$(GCC)@ ;s@)gcc@)$(PROJECTROOT)/$(GCC)@' -i busybox/Makefile
	make HOSTCFLAGS=-static HOSTLDFLAGS=-static -C busybox

clean:
	rm -Rf usr/bin/* usr/lib/* usr/include/*
	make -C busybox clean
	make -C buildMusl clean
