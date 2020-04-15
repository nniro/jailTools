#! /bin/sh

CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=$(MUSLOBJECTS) $(MUSLGCC)
BUSYBOX=busybox/busybox
ZLIB=zlib/libz.a
SSHD=openssh/sshd
LDFLAGS=-static
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

ALL: busybox/configure $(BUSYBOX) $(SSHD)

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

zlib/configure: $(MUSL)
	git submodule init zlib
	git submodule update zlib

$(ZLIB): zlib/configure $(MUSL)
	sh -c 'cd zlib; CC=$(PROJECTROOT)/$(GCC) ./configure --static'
	make -C zlib

openssh/configure: $(MUSL) $(ZLIB) $(BUSYBOX)
	git submodule init openssh
	git submodule update openssh
	sh -c 'cd openssh; autoconf; autoheader'

$(SSHD): openssh/configure $(MUSL) $(ZLIB)
	sh -c 'cd openssh; CC=$(PROJECTROOT)/$(GCC) CFLAGS="-static -Os" LDFLAGS="-static" ./configure --host="$(shell $(PROJECTROOT)/$(GCC) -dumpmachine)" --prefix=/ --sysconfdir=/etc/ssh/ --with-zlib=$(PROJECTROOT)/zlib --without-openssl --without-openssl-header-check'
	make -C openssh

clean:
	make -C buildMusl clean
	make -C busybox clean
	sh -c 'cd busybox; git checkout Makefile'
	make -C zlib clean
	make -C openssh clean
	rm -Rf usr/bin/* usr/lib/* usr/include/*
