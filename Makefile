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

stamp/fetch-tiny-loader: | src stamp
	cd src && git clone https://github.com/guineawheek/tiny-floppy-bootloader.git
	cd src/tiny-floppy-bootloader && git -c advice.detachedHead=false checkout 6f7b7c64386c5203fd54804b87288503e11b8575
	cd src/tiny-floppy-bootloader && for patch in ../../patches/tiny-floppy-loader/*.patch; do\
		patch -p1 < $$patch; \
	done
	touch $@

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

build-mini-busybox: out/initramfs/bin/busybox

build-busybox: out/busybox/bin/busybox

BUSYBOX_SETTINGS = $(KERNEL_SETTINGS)

out/busybox/bin/busybox: config/busybox.config | stamp/fetch-busybox out
	cp config/busybox.config src/$(BUSYBOX_DIR)/.config
	$(MAKE) -C src/$(BUSYBOX_DIR) $(BUSYBOX_SETTINGS)
	$(MAKE) -C src/$(BUSYBOX_DIR) $(BUSYBOX_SETTINGS) CONFIG_PREFIX=../../out/busybox install

out/initramfs/bin/busybox: config/busybox.mini.config | stamp/fetch-busybox out out/initramfs
	cp config/busybox.mini.config src/$(BUSYBOX_DIR)/.config
	$(MAKE) -C src/$(BUSYBOX_DIR) ARCH=x86 CROSS_COMPILE=i486-linux-musl- AR=i486-linux-musl-gcc-ar NM=i486-linux-musl-gcc-nm
	$(MAKE) -C src/$(BUSYBOX_DIR) ARCH=x86 CROSS_COMPILE=i486-linux-musl- AR=i486-linux-musl-gcc-ar NM=i486-linux-musl-gcc-nm CONFIG_PREFIX=../../out/initramfs install

out/initramfs/etc/init.d/%: etc/% | out/initramfs/etc/init.d
	cp $< $@
	chmod +x $@

out/initramfs/dev: | out/initramfs
	cd out/initramfs && mkdir dev

build-initramfs: $(ROOT_DIR)/out/initramfs.cpio

$(ROOT_DIR)/out/initramfs.cpio: | out/initramfs  out/initramfs/dev
	cd out/initramfs && find . | cpio -o -H newc > $(ROOT_DIR)/out/initramfs.cpio # | xz --check=crc32 -1e

out/initramfs/bin/flmount: src/flmount/mount.c
	i486-linux-musl-gcc -static -o $@ $<

build-floppy: out/bzImage $(ROOT_DIR)/out/initramfs.cpio build-syslinux | out
	dd if=/dev/zero of=./floppy_linux.img bs=1k count=1440
	mkdosfs floppy_linux.img
	out/syslinux/usr/bin/syslinux --install floppy_linux.img
	mcopy -i floppy_linux.img config/syslinux.cfg ::
	mcopy -i floppy_linux.img out/bzImage  ::
	mcopy -i floppy_linux.img out/initramfs.cpio.xz  ::rootfs.ram

build-tiny-floppy: stamp/fetch-tiny-loader | out
	@cd src/tiny-floppy-bootloader && OUTPUT="../../out/tinydisk.img" KERN="../../out/bzImage" ./build.sh

build-kernel-modules: stamp/fetch-kernel config/kernel.config
	$(MAKE) -C src/$(LINUX_DIR) INSTALL_MOD_PATH=../../out/kmodules/ ARCH=x86 CROSS_COMPILE=i486-linux-musl- modules
	$(MAKE) -C src/$(LINUX_DIR) INSTALL_MOD_PATH=../../out/kmodules/ ARCH=x86 CROSS_COMPILE=i486-linux-musl- modules_install

build-aux-floppy: out/busybox/bin/busybox build-kernel-modules
	cd out/busybox && mksquashfs * ../kmodules/* ../aux_bb.img -root-owned -comp xz -noappend -nopad -no-xattrs -no-exports
	@if [ `stat -c %s aux_bb.img` -gt 1474560 ]; then \
		echo "Auxiliary Image exceeds 1.44MB. Cannot fit on floppy"; \
		exit 1;\
	fi
	truncate -s 1440K out/aux_bb.img

clean:
	echo "Making a fresh build ..."
	-rm -rf src dist stamp out
