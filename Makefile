#! /bin/sh

PROJECTROOT=$(PWD)
CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990
MUSLGCC=$(PROJECTROOT)/usr/bin/musl-gcc
MUSL=$(PROJECTROOT)/usr/lib/libc.a
BUSYBOX=$(PROJECTROOT)/busybox/busybox
ZLIB=zlib
SSHD=sshd
SECCOMP=seccomp
LDFLAGS=-static
MUZZLER=
MUZZLER_CLEAN=

.PHONY: $(MUSL) $(BUSYBOX) $(ZLIB) $(SECCOMP) $(SSHD)

hasMeson=$(shell which meson >/dev/null 2>/dev/null && echo yes || echo no)

ifeq ($(hasMeson),yes)
	MUZZLER=muzzler
	MUZZLER_CLEAN=muzzler_clean
.PHONY: $(MUZZLER) $(MUZZLER_CLEAN)
endif

ALL: $(BUSYBOX) $(MUSL)

.ready:
	$(shell sh checkExist.sh)

musl/.ready: .ready
	git submodule init musl
	git submodule update musl
	sh -c 'cd musl; ./configure --prefix=$(PROJECTROOT)/usr'
	touch musl/.ready

$(MUSL): musl/.ready
	$(MAKE) -C musl
	$(MAKE) -C musl install

busybox/Makefile: $(MUSL)
	git submodule init busybox
	git submodule update busybox

busybox/.ready: busybox/Makefile $(MUSL)
	cp busybox.config busybox/.config
	sh -c 'cd busybox; git apply $(PROJECTROOT)/patches/busybox/*.patch 2>/dev/null; exit 0'
	sed -e 's@ gcc@ $(MUSLGCC)@ ;s@)gcc@)$(MUSLGCC)@' -i $(PROJECTROOT)/busybox/Makefile
	touch busybox/.ready

$(BUSYBOX): busybox/.ready
	-ln -sf /usr/include/linux usr/include/
	$(if $(shell sh $(PROJECTROOT)/checkAsm.sh $(MUSLGCC)), ,$(error Could not find the directory 'asm' in either '/usr/include/' or '/usr/include/$(shell $(MUSLGCC) -dumpmachine)/'))
	-ln -sf /usr/include/asm-generic usr/include/
	$(MAKE) HOSTCFLAGS=-static HOSTLDFLAGS=-static -C busybox

zlib/configure: $(MUSL)
	git submodule init zlib
	git submodule update zlib

zlib/Makefile: zlib/configure
	sh -c 'cd zlib; CC=$(MUSLGCC) ./configure --static'

$(ZLIB): zlib/Makefile $(MUSL)
	$(MAKE) -C zlib

openssh/configure: $(ZLIB) $(MUSL)
	git submodule init openssh
	git submodule update openssh

openssh/Makefile: openssh/configure
	sh -c 'cd openssh; autoconf; autoheader'
	sh -c 'cd openssh; CC=$(MUSLGCC) CFLAGS="-static -Os" LDFLAGS="-static" ./configure --host="$(shell $(MUSLGCC) -dumpmachine)" --prefix=/ --sysconfdir=/etc/ssh/ --with-zlib=$(PROJECTROOT)/zlib --without-openssl --without-openssl-header-check'

$(SSHD): openssh/Makefile $(ZLIB) $(MUSL)
	$(MAKE) -C openssh

libseccomp/configure: $(MUSL)
	git submodule init libseccomp
	git submodule update libseccomp

libseccomp/Makefile: libseccomp/configure
	sh -c 'cd libseccomp; sh autogen.sh'
	sh -c 'cd libseccomp; CC=$(MUSLGCC) CFLAGS="-static -Os" LDFLAGS="-static" ./configure --prefix=$(PROJECTROOT)/usr'

$(SECCOMP): libseccomp/Makefile $(MUSL)
	$(MAKE) -C libseccomp
	$(MAKE) -C libseccomp install

mesonNative:
	echo "[binaries]\nc = '$(PROJECTROOT)/usr/bin/musl-gcc'" > mesonNative

buildMuzzler/build.ninja: mesonNative $(SECCOMP) $(MUSL)
	meson --prefix=$(PROJECTROOT)/usr --native-file mesonNative ./muzzler buildMuzzler

$(MUZZLER): buildMuzzler/build.ninja $(SECCOMP) $(MUSL)
	ninja -C buildMuzzler install

$(MUZZLER_CLEAN):
	-ninja -C buildMuzzler clean
	rm -Rf buildMuzzler

.PHONY: clean
clean: $(MUZZLER_CLEAN)
	-$(MAKE) -C musl clean
	-rm musl/.ready
	-$(MAKE) -C busybox clean
	-sh -c 'cd busybox; git reset --hard; rm .ready'
	-$(MAKE) -C zlib clean
	-$(MAKE) -C openssh clean
	-$(MAKE) -C libseccomp clean
	rm -Rf usr/bin/* usr/lib/* usr/include/*
	rm .ready
