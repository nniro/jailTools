#! /bin/sh

CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990
MUSLGCC=usr/bin/musl-gcc
MUSLOBJECTS=usr/lib/libc.a
MUSL=musl
BUSYBOX=busybox
ZLIB=zlib
SSHD=sshd
LDFLAGS=-static
GCC=$(MUSLGCC)
PROJECTROOT=$(PWD)

.PHONY: $(MUSL) $(BUSYBOX) $(ZLIB) $(SSHD)

ALL: $(SSHD) $(BUSYBOX) $(MUSL)

musl/configure:
	git submodule init musl
	git submodule update musl
	sh -c 'cd musl; ./configure --prefix=$(PROJECTROOT)/usr'

$(MUSL): musl/configure
	$(MAKE) -C musl
	$(MAKE) -C musl install

busybox/Makefile: $(MUSL)
	git submodule init busybox
	git submodule update busybox

busybox/.ready: busybox/Makefile
	cp busybox.config busybox/.config
	sh -c 'cd busybox; git apply $(PROJECTROOT)/patches/busybox/*.patch 2>/dev/null; exit 0'
	sed -e 's@ gcc@ $(PROJECTROOT)/$(GCC)@ ;s@)gcc@)$(PROJECTROOT)/$(GCC)@' -i busybox/Makefile
	touch busybox/.ready

$(BUSYBOX): busybox/.ready $(MUSL)
	-ln -sf /usr/include/linux usr/include/
	-ln -sf /usr/include/asm usr/include/
	-ln -sf /usr/include/asm-generic usr/include/
	$(MAKE) HOSTCFLAGS=-static HOSTLDFLAGS=-static -C busybox

zlib/configure: $(MUSL)
	git submodule init zlib
	git submodule update zlib

zlib/Makefile: zlib/configure
	sh -c 'cd zlib; CC=$(PROJECTROOT)/$(GCC) ./configure --static'

$(ZLIB): zlib/Makefile $(MUSL)
	$(MAKE) -C zlib

openssh/configure: $(ZLIB) $(MUSL)
	git submodule init openssh
	git submodule update openssh

openssh/Makefile: openssh/configure
	sh -c 'cd openssh; autoconf; autoheader'
	sh -c 'cd openssh; CC=$(PROJECTROOT)/$(GCC) CFLAGS="-static -Os" LDFLAGS="-static" ./configure --host="$(shell $(PROJECTROOT)/$(GCC) -dumpmachine)" --prefix=/ --sysconfdir=/etc/ssh/ --with-zlib=$(PROJECTROOT)/zlib --without-openssl --without-openssl-header-check'

$(SSHD): openssh/Makefile $(ZLIB) $(MUSL)
	$(MAKE) -C openssh

.PHONY: clean
clean:
	$(MAKE) -C musl clean
	$(MAKE) -C busybox clean
	sh -c 'cd busybox; git reset --hard; rm .ready'
	$(MAKE) -C zlib clean
	$(MAKE) -C openssh clean
	rm -Rf usr/bin/* usr/lib/* usr/include/*
