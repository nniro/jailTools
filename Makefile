#! /bin/sh

PROJECTROOT=$(PWD)

MUSLGCC=$(PROJECTROOT)/usr/bin/musl-gcc
MUSL=$(PROJECTROOT)/usr/lib/libc.a
MUSL_BUILD_ROOT=$(PROJECTROOT)/build/musl
BUSYBOX_BUILD_ROOT=$(PROJECTROOT)/build/busybox
BUSYBOX=$(BUSYBOX_BUILD_ROOT)/busybox
SUPERSCRIPT=$(addprefix $(PROJECTROOT)/busybox/embed/, jt)
EMBEDDED_SCRIPTS=$(addprefix $(PROJECTROOT)/scripts/,\
config.sh\
cpDep.sh\
readElf.sh\
jailUpgrade.sh\
newJail.sh\
utils.sh\
jailLib.template.sh\
startRoot.template.sh\
filesystem.template.sh\
rootCustomConfig.template.sh\
rootDefaultConfig.template.sh\
)
ZLIB=zlib
SSHD=sshd
SECCOMP=seccomp
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

$(MUSL_BUILD_ROOT)/.ready: .ready
	git submodule init musl
	git submodule update musl
	mkdir -p $(MUSL_BUILD_ROOT)
	sh -c 'cd $(MUSL_BUILD_ROOT); $(PROJECTROOT)/musl/configure --prefix=$(PROJECTROOT)/usr'
	touch $(MUSL_BUILD_ROOT)/.ready

$(MUSL): $(MUSL_BUILD_ROOT)/.ready
	$(MAKE) -C $(MUSL_BUILD_ROOT)
	$(MAKE) -C $(MUSL_BUILD_ROOT) install

busybox/Makefile: $(MUSL)
	git submodule init busybox
	git submodule update busybox

busybox/embed: busybox/Makefile $(MUSL)
	mkdir -p busybox/embed

$(BUSYBOX_BUILD_ROOT)/.ready: busybox/Makefile busybox/embed $(MUSL)
	mkdir -p $(BUSYBOX_BUILD_ROOT)
	sh -c 'cd busybox; git apply $(PROJECTROOT)/patches/busybox/*.patch 2>/dev/null; exit 0'
	touch $(BUSYBOX_BUILD_ROOT)/.ready

# we want this to be ran unconditionnally
.PHONY: $(PROJECTROOT)/busybox/embed/jt

$(PROJECTROOT)/busybox/embed/jt: scripts/jailtools.template.sh busybox/embed $(PROJECTROOT)/embedJT.sh $(EMBEDDED_SCRIPTS)
	rm -f $(PROJECTROOT)/busybox/embed/jt
	sh $(PROJECTROOT)/embedJT.sh $(PROJECTROOT)/busybox/embed jt

$(BUSYBOX): $(SUPERSCRIPT) $(BUSYBOX_BUILD_ROOT)/.ready
	-ln -sf /usr/include/linux $(PROJECTROOT)/usr/include/
	$(if $(shell sh $(PROJECTROOT)/checkAsm.sh $(MUSLGCC)), ,$(error Could not find the directory 'asm' in either '/usr/include/' or '/usr/include/$(shell $(MUSLGCC) -dumpmachine)/'))
	-ln -sf /usr/include/asm-generic $(PROJECTROOT)/usr/include/
	sh -c 'cd $(BUSYBOX_BUILD_ROOT); make KBUILD_DEFCONFIG=$(PROJECTROOT)/busybox.config KBUILD_SRC=$(PROJECTROOT)/busybox -f $(PROJECTROOT)/busybox/Makefile defconfig'
	$(MAKE) HOSTCC=$(MUSLGCC) CC=$(MUSLGCC) HOSTCFLAGS=-static HOSTLDFLAGS=-static -C $(BUSYBOX_BUILD_ROOT)
	printf "#! /bin/sh\n\nbb=$(BUSYBOX)" > $(PROJECTROOT)/scripts/paths.sh
	# this is for being backward compatible with the old busybox emplacement so upgrading is possible, this should be removed soonish
	ln -sfT $(BUSYBOX) $(PROJECTROOT)/busybox/busybox

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
	echo "[binaries]\nc = ['$(PROJECTROOT)/usr/bin/musl-gcc', '-Wl,--dynamic-linker=$(PROJECTROOT)/usr/lib/libc.so']" > mesonNative

build/muzzler/build.ninja: mesonNative $(SECCOMP) $(MUSL)
	meson --prefix=$(PROJECTROOT)/usr --native-file mesonNative ./muzzler build/muzzler

$(MUZZLER): build/muzzler/build.ninja $(SECCOMP) $(MUSL)
	ninja -C build/muzzler install

$(MUZZLER_CLEAN):
	-ninja -C build/muzzler clean
	rm -Rf build/muzzler

.PHONY: clean
clean: $(MUZZLER_CLEAN)
	-sh -c 'cd build && rm -Rf musl'
	-sh -c 'cd busybox && git reset --hard'
	-rm busybox/busybox
	-sh -c 'cd build && rm -Rf busybox'
	-$(MAKE) -C zlib clean
	-$(MAKE) -C openssh clean
	-$(MAKE) -C libseccomp clean
	rm -Rf usr/bin/* usr/lib/* usr/include/*
	rm .ready
