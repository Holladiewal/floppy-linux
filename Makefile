ROOT_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
INITRAMFS_BASE=$(ROOT_DIR)/out/initramfs

.SUFFIXES:

UBUNTU_SYSLINUX_ORIG=http://archive.ubuntu.com/ubuntu/pool/main/s/syslinux/syslinux_6.04~git20190206.bf6db5b4+dfsg1.orig.tar.xz
UBUNTU_SYSLINUX_PKG=http://archive.ubuntu.com/ubuntu/pool/main/s/syslinux/syslinux_6.04~git20190206.bf6db5b4+dfsg1-3ubuntu1.debian.tar.xz

LINUX_DIR=linux-6.4
LINUX_TARBALL=$(LINUX_DIR).tar.xz
LINUX_KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/$(LINUX_TARBALL)

BUSYBOX_DIR=busybox-1.36.1
BUSYBOX_TARBALL=$(BUSYBOX_DIR).tar.bz2
BUSYBOX_URL=https://busybox.net/downloads/$(BUSYBOX_TARBALL)

subdirs = dist src out stamp out/initramfs out/initramfs/etc out/initramfs/etc/init.d out/initramfs/sys temp/syslinux

.PHONY: all clean build-busybox 

all: stamp/fetch-kernel \
	 stamp/fetch-busybox

	-mkdir -p stamp
	echo "Starting build ..."

$(subdirs): 
	-mkdir -p $@

stamp/fetch-kernel dist/$(LINUX_TARBALL) src/$(LINUX_DIR): | dist src stamp
	cd dist && wget $(LINUX_KERNEL_URL)
	cd src && tar -xvf ../dist/$(LINUX_TARBALL)
	touch stamp/fetch-kernel		

stamp/fetch-busybox dist/$(BUSYBOX_TARBALL) src/$(BUSYBOX_DIR): | dist src stamp
	cd dist && wget $(BUSYBOX_URL)
	cd src && tar -xvf ../dist/$(BUSYBOX_TARBALL)
	touch stamp/fetch-busybox		


stamp/fetch-syslinux: | dist src stamp temp/syslinux
	cd dist && wget $(UBUNTU_SYSLINUX_ORIG) -O syslinux_orig.tar.xz
	cd dist && wget $(UBUNTU_SYSLINUX_PKG) -O syslinux_pkg.tar.xz
	cd src && tar -xvf ../dist/syslinux_orig.tar.xz
	cd src && mv syslinux-6.04~git20190206.bf6db5b4 syslinux
	cd temp/syslinux && tar -xvf ../../dist/syslinux_pkg.tar.xz
	cp temp/syslinux/debian/patches/*.patch patches/syslinux
	rm -r temp/syslinux
	touch $@

kernelmenuconfig: | stamp/fetch-kernel
	cp config/kernel.config src/$(LINUX_DIR)/.config
	cd src/$(LINUX_DIR) && make ARCH=x86 CROSS_COMPILE=i486-linux-musl- menuconfig
	cp src/$(LINUX_DIR)/.config config/kernel.config

busyboxmenuconfig: | stamp/fetch-busybox
	cp config/busybox.config src/$(BUSYBOX_DIR)/.config
	cd src/$(BUSYBOX_DIR) && make ARCH=x86 CROSS_COMPILE=i486-linux-musl- menuconfig
	cp src/$(BUSYBOX_DIR)/.config config/busybox.config

build-syslinux: out/syslinux/usr/bin/syslinux
patch-syslinux: stamp/patched-syslinux

stamp/patched-syslinux: stamp/fetch-syslinux patches/syslinux/*.patch
	cd src/syslinux && for patch in ../../patches/syslinux/*.patch; do\
		patch -p1 < $$patch; \
	done
	touch $@

out/syslinux/usr/bin/syslinux: | stamp/fetch-syslinux out patch-syslinux
	cd src/syslinux && make bios PYTHON=python3 
	cd src/syslinux && make bios install INSTALLROOT=`pwd`/../../out/syslinux PYTHON=python3

build-kernel: out/bzImage

KERNEL_SETTINGS = ARCH=x86 CROSS_COMPILE=i486-linux-musl- AR=i486-linux-musl-gcc-ar NM=i486-linux-musl-gcc-nm
out/bzImage: config/kernel.config | stamp/fetch-kernel  build-busybox build-initramfs out
	cp config/kernel.config src/$(LINUX_DIR)/.config
	cd src/$(LINUX_DIR) && $(MAKE) $(KERNEL_SETTINGS)
	cp src/$(LINUX_DIR)/arch/x86/boot/bzImage out/bzImage

build-busybox: stamp/fetch-busybox
	-mkdir -p out/initramfs
	cp config/busybox.config src/$(BUSYBOX_DIR)/.config
	cd src/$(BUSYBOX_DIR) && $(MAKE) -j4 ARCH=x86 CROSS_COMPILE=i486-linux-musl-
	cd src/$(BUSYBOX_DIR) && $(MAKE) -j4 ARCH=x86 CROSS_COMPILE=i486-linux-musl- install
	cp -rv src/$(BUSYBOX_DIR)/_install/* out/initramfs

build-initramfs:
	-rm -rf out/initramfs/dev
	-mkdir -p out/initramfs/dev

	-rm -rf out/initramfs/sys
	-mkdir -p out/initramfs/sys

	-rm -rf out/initramfs/proc
	-mkdir -p out/initramfs/proc

	mkdir -p out/initramfs/etc/init.d/
	cp etc/rc out/initramfs/etc/init.d/rc
	chmod +x out/initramfs/etc/init.d/rc

	cp etc/inittab out/initramfs/etc/inittab
	chmod +x out/initramfs/etc/inittab

	cd out/initramfs && \
	find . | cpio -o -H newc | bzip2 -9 > $(ROOT_DIR)/out/initramfs.cpio.bz2

build-floppy: build-kernel build-initramfs build-syslinux
	dd if=/dev/zero of=./floppy_linux.img bs=1k count=1440
	mkdosfs floppy_linux.img
	out/syslinux/usr/bin/syslinux --install floppy_linux.img
	mcopy -i floppy_linux.img config/syslinux.cfg ::
	mcopy -i floppy_linux.img out/bzImage  ::
	mcopy -i floppy_linux.img out/initramfs.cpio.bz2  ::rootfs.ram

clean:
	echo "Making a fresh build ..."
	-rm -rf src dist stamp out
