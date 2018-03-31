#!/bin/bash

set -e

# Colors!
export C_CLEAR='\e[m'
export C_RED='\e[1;31m'
export C_GREEN='\e[1;32m'

message() {
	echo -e " ${C_GREEN}>>${C_CLEAR} ${@}"
}

error() {
	echo -e " ${C_RED}>>${C_CLEAR} ${@}"
}

configure_arch() {
	case $BARCH in
		x86_64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="x86_64-linux-musl"
			export XKARCH="x86_64"
			export GCCOPTS="--with-arch=x86-64 --with-tune=generic --enable-long-long"
			;;
		i686)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="i686-linux-musl"
			export XKARCH="i386"
			export GCCOPTS="--with-arch=i686 --with-tune=generic"
			;;
		aarch64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="aarch64-linux-musl"
			export XKARCH="arm64"
			export GCCOPTS="--with-arch=armv8-a --with-abi=lp64"
			;;
		armv7l)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="arm-linux-musleabihf"
			export XKARCH="arm"
			export GCCOPTS="--with-arch=armv7-a --with-float=hard --with-fpu=neon"
			;;
		mips64el)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mips64el-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips3 --with-tune=mips64 --with-mips-plt --with-float=soft --with-abi=64"
			;;
		mipsel)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="mipsel-linux-musl"
			export XKARCH="mips"
			export GCCOPTS="--with-arch=mips32 --with-mips-plt --with-float=soft --with-abi=32"
			;;
		powerpc64)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc64-linux-musl"
			export XKARCH="powerpc64"
			export GCCOPTS="--with-abi=elfv2 --enable-secureplt --enable-decimal-float=no"
			;;
		powerpc)
			export XHOST="$(echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/')"
			export XTARGET="powerpc-linux-musl"
			export XKARCH="powerpc"
			export GCCOPTS="--enable-secureplt --enable-decimal-float=no"
			;;
		*)
			error "BARCH variable isn't set!"
			exit 0
	esac
}

setup_build_env() {
	message "Preparing build environment..."
	sleep 1
	export CWD="$(pwd)"
	export BUILD="$CWD/build"
	export SOURCES="$BUILD/sources"
	export ROOTFS="$BUILD/rootfs"
	export TOOLS="$BUILD/tools"
	export PKGS="$BUILD/packages"
	export KEEP="$CWD/KEEP"
	export REPO="$CWD/pkgs"
	export TC="$CWD/toolchain"
	export UTILS="$CWD/utils"

	rm -rf $BUILD
	mkdir -p $BUILD $SOURCES $ROOTFS $TOOLS $PKGS

	export LC_ALL="POSIX"
	export PATH="$UTILS:$TOOLS/bin:$PATH"
	export MKOPTS="-j$(expr $(nproc) + 1)"
	export HOSTCC="gcc"
}

prepare_toolchain_and_rootfs() {
	message "Setting up toolchain optimizations..."
	sleep 1
	export CFLAGS="-Os -g0"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="-s"

	case $BARCH in
		x86_64|aarch64|mips64el|powerpc64)
			cd $TOOLS
			mkdir -p $TOOLS/lib
			ln -s lib lib64
			mkdir -p $TOOLS/$XTARGET/lib
			cd $TOOLS/$XTARGET
			ln -s lib lib64
			;;
	esac

	cd $TOOLS
	ln -sf . usr
}

build_toolchain() {
	message "Setting up filesystem..."
	sleep 1
	. $UTILS/setup-rootfs

	message "Building cross-toolchain for $XTARGET..."
	sleep 1
	MODE=toolchain buildpkg $TC/file
	MODE=toolchain buildpkg $TC/pkgconf
	MODE=third buildpkg $REPO/linux-headers $PKGS/linux-headers
	MODE=toolchain buildpkg $TC/binutils
	MODE=toolchain buildpkg $TC/gcc-static
	MODE=third buildpkg $REPO/musl $PKGS/musl
	MODE=toolchain buildpkg $TC/gcc-final
}

finish_toolchain() {
	message "Finishing toolchain..."
	rm -rf $SOURCES/*
	find $TOOLS -type f | xargs file 2>/dev/null | grep "LSB executable"       | cut -f 1 -d : | xargs strip --strip-all	2>/dev/null || true
	find $TOOLS -type f | xargs file 2>/dev/null | grep "shared object"        | cut -f 1 -d : | xargs strip --strip-unneeded	2>/dev/null || true
	find $TOOLS -type f | xargs file 2>/dev/null | grep "current ar archive"   | cut -f 1 -d : | xargs strip --strip-debug	2>/dev/null || true
	message "Toolchain successfully built!"
}

prepare_build() {
	message "Setting up optimzations and toolset for rootfs build..."
	sleep 1
	export CFLAGS="$CFLAGS"
	export CXXFLAGS="$CFLAGS"
	export LDFLAGS="$LDFLAGS"
	export CC="$XTARGET-gcc"
	export CXX="$XTARGET-g++"
	export AR="$XTARGET-ar"
	export AS="$XTARGET-as"
	export LD="$XTARGET-ld"
	export RANLIB="$XTARGET-ranlib"
	export READELF="$XTARGET-readelf"
	export STRIP="$XTARGET-strip"
}

build_rootfs() {
	case $BARCH in
		x86_64|i686)
			export BOOTPKG="linux grub"
			;;
		aarch64|armv7l)
			error "No kernel and bootloader for $BARCH"
			exit 0
			;;
		mips64el|mipsel)
			error "No kernel and bootloader for $BARCH"
			exit 0
			;;
		powerpc64|powerpc)
			error "No kernel and bootloader for $BARCH"
			exit 0
			;;
	esac

	message "Building rootfs..."
	sleep 1
#	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap sed pkgconf ncurses util-linux iana-etc libtool iproute2 bzip2 perl readline autoconf automake bash bc file gawk grep less kbd make xz kmod expat patch gperf eudev busybox xfsprogs $BOOTPKG vim gdb libffi python sudo parted mc cmake libressl libnl wpa_supplicant dhcp openssh curl git rsync libarchive lynx libevent tmux alsa-lib alsa-utils libav mplayer; do
#		buildpkg $REPO/$PKG $PKGS/$PKG
#	done

	for PKG in zlib m4 bison flex libelf binutils gmp mpfr mpc gcc attr acl libcap sed pkgconf ncurses util-linux iana-etc libtool iproute2 bzip2 perl readline autoconf automake bash bc file gawk grep less kbd make xz kmod expat patch gperf eudev busybox xfsprogs $BOOTPKG; do
		buildpkg $REPO/$PKG $PKGS/$PKG
	done
}

configure_arch
setup_build_env
prepare_toolchain_and_rootfs
build_toolchain
finish_toolchain
prepare_build
build_rootfs

exit 0

