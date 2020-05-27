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

ALL: $(BUSYBOX) $(SSHD)

musl/configure:
	git submodule init musl
	git submodule update musl

busybox/Makefile: $(MUSL)
	git submodule init busybox
	git submodule update busybox
	ln -sf /usr/include/linux usr/include/
	ln -sf /usr/include/asm usr/include/
	ln -sf /usr/include/asm-generic usr/include/

musl/lib/libc.so: musl/configure
	sh -c 'cd musl; ./configure --prefix=$(PROJECTROOT)/usr'
	make -C musl

$(MUSL): musl/lib/libc.so
	make -C musl install

$(BUSYBOX): $(MUSL) busybox/Makefile
	cp busybox.config busybox/.config
	sh -c 'cd busybox; git apply $(PROJECTROOT)/patches/busybox/*.patch 2>/dev/null; exit 0'
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
	make -C musl clean
	make -C busybox clean
	sh -c 'cd busybox; git reset --hard'
	make -C zlib clean
	make -C openssh clean
	rm -Rf usr/bin/* usr/lib/* usr/include/*
