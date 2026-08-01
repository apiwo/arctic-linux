#!/bin/sh
# Arctic Linux - the tools that make the installer actually usable.
#
# First-run feedback found the image could not do the basic job:
#   - no cfdisk, no sfdisk, no wipefs        (nothing to partition with)
#   - busybox mke2fs only makes ext2         (so no real mkfs.ext4, and a
#                                             partition with no filesystem is
#                                             exactly why "mount /dev/sdb1 /mnt"
#                                             failed)
#   - no iwctl and no firmware at all        (so wireless could never work)
#
# This builds the missing pieces. Everything installs into the same rootfs the
# ISO is made from.
set -u

if [ "${ARCTIC_SANDBOX:-0}" != "1" ]; then
	echo "refusing to build outside the sandbox - use arctic/build/arctic-sandbox" >&2
	exit 1
fi

B=/home/apiwo/arctic-build
SRC=$B/src
W=$B/work
R=$B/stage/rootfs
DEPS=$B/stage/deps
L=$B/logs
J=$(nproc)

step() { printf '\n\033[1;36m:: %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32mok\033[0m %s\n' "$*"; }
bad()  { printf '   \033[31mFAILED\033[0m %s\n' "$*"; }

unpack() { [ -d "$W/$1" ] && return 0; tar -xf "$SRC/$2" -C "$W"; }

export CFLAGS="-O2 -pipe -fstack-protector-strong"
export CXXFLAGS="$CFLAGS"

# ------------------------------------------------------------------ util-linux
# cfdisk, sfdisk, wipefs, lsblk, blkid, mount, umount, findmnt, and the real
# libblkid/libmount that e2fsprogs and iwd expect.
step "building util-linux 2.42.2 (cfdisk, sfdisk, wipefs, lsblk, blkid)"
if [ ! -x "$R/usr/bin/cfdisk" ]; then
	unpack util-linux-2.42.2 util-linux-2.42.2.tar.xz
	# cfdisk needs a curses library and libsmartcols (lsblk, findmnt, ...) wants
	# terminfo for column widths. Without PKG_CONFIG_PATH pointing at $DEPS,
	# configure happily finds the build host's GNU ncurses instead - Arctic
	# ships none of that, only netbsd-curses (README: "terminal library:
	# netbsd-curses, not ncurses") - and the result is a cfdisk/lsblk that
	# fail on the target with "error while loading shared libraries:
	# libncursesw.so.6 / libtinfow.so.6: cannot open shared object file".
	# $DEPS/usr/lib/pkgconfig/ncursesw.pc points back at netbsd-curses, whose
	# real SONAME is plain "libcurses.so" - already shipped in the base image -
	# so linking against it here resolves cleanly on the target.
	#
	# util-linux's ncurses probe (UL_NCURSES_CHECK) tries ncursesw6-config
	# before pkg-config, and this build host has one: it hands back the
	# host's own "-I/usr/include/ncursesw", bypassing PKG_CONFIG_PATH for the
	# header side while the library side still resolves through pkg-config to
	# Arctic's libs. Host headers plus Arctic's library disagree on how
	# curses globals like acs_map are exposed, and cfdisk fails to link with
	# "undefined reference to acs_map". Forcing the *_CONFIG tools to "false"
	# pushes the probe straight to pkg-config, so header and library come
	# from the same (Arctic) place.
	( cd "$W/util-linux-2.42.2" && \
	  PKG_CONFIG_PATH="$DEPS/usr/lib/pkgconfig" \
	  CFLAGS="$CFLAGS -I$DEPS/usr/include" \
	  LDFLAGS="-L$DEPS/usr/lib -Wl,-rpath-link,$DEPS/usr/lib" \
	  NCURSESW6_CONFIG=false NCURSESW5_CONFIG=false \
	  NCURSES6_CONFIG=false NCURSES5_CONFIG=false \
	  ./configure --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
		--libdir=/usr/lib --disable-static --disable-nls --disable-rpath \
		--without-python --without-systemd --without-udev \
		--disable-liblastlog2 --disable-pam-lastlog2 \
		--enable-libblkid --enable-libmount --enable-libuuid \
		--enable-cfdisk --enable-fdisk --enable-sfdisk --enable-wipefs \
		--enable-lsblk --enable-blkid --enable-findmnt --enable-partx \
		--disable-login --disable-su --disable-runuser --disable-chfn-chsh \
		--disable-write --disable-wall --disable-mesg --disable-sulogin \
		--disable-setterm --disable-more --disable-ul --disable-scriptutils \
		--disable-last --disable-utmpdump --without-readline \
	  && make -j"$J" \
	) >"$L/util-linux.log" 2>&1 && {
		d=$W/util-linux-2.42.2
		# Copy the built artefacts directly. "make install" relinks with libtool
		# and fails on libmount.la; the binaries are already correct, and Arctic
		# only wants the partitioning and block-device tools anyway.
		#
		# Every one of these links against an uninstalled libtool library
		# (libmount.la, libblkid.la, ...), so the file libtool leaves at the top
		# of the build directory - $d/$t - is not the binary. It is a shell
		# script: "temporary wrapper script for .libs/$t ... should never be
		# moved out of the build directory." Moving it anyway is exactly what
		# happened here, and it is why cfdisk and friends failed on a booted
		# image with a wrapper-script error instead of running. The real ELF is
		# at $d/.libs/$t.
		for t in cfdisk sfdisk fdisk wipefs lsblk blkid findmnt partx \
		         mkswap swapon swapoff losetup; do
			src="$d/.libs/$t"
			[ -f "$src" ] || src="$d/$t"
			[ -f "$src" ] || continue
			# busybox owns some of these names as symlinks; the real tool wins.
			[ -L "$R/usr/bin/$t" ] && rm -f "$R/usr/bin/$t"
			install -Dm755 "$src" "$R/usr/bin/$t"
		done
		for lib in "$d"/.libs/lib*.so.*; do
			[ -f "$lib" ] || continue
			cp -a "$lib" "$R/usr/lib/" 2>/dev/null || :
			cp -a "$lib" "$DEPS/usr/lib/" 2>/dev/null || :
		done
		# Recreate the unversioned links the loader and linker expect.
		for base in libblkid libmount libuuid libsmartcols libfdisk; do
			so=$(ls "$R/usr/lib/$base.so."* 2>/dev/null | head -1)
			[ -n "$so" ] && ln -sf "$(basename "$so")" "$R/usr/lib/$base.so"
		done
		[ -x "$R/usr/bin/cfdisk" ] && ok "util-linux (cfdisk, sfdisk, wipefs, lsblk)" \
			|| bad "util-linux (binaries not produced)"
	} || bad "util-linux (see logs/util-linux.log)"
else
	ok "util-linux already built"
fi

# ------------------------------------------------------------------- e2fsprogs
step "building e2fsprogs (a real mkfs.ext4, not busybox's ext2-only mke2fs)"
if [ ! -x "$R/usr/bin/mke2fs" ] || [ -L "$R/usr/bin/mke2fs" ]; then
	unpack e2fsprogs-1.47.4 e2fsprogs.tar.gz
	d=$(ls -d "$W"/e2fsprogs-* 2>/dev/null | head -1)
	( cd "$d" && \
	  ./configure --prefix=/usr --bindir=/usr/bin --sbindir=/usr/bin \
		--libdir=/usr/lib --with-root-prefix=/usr --disable-nls \
		--disable-libblkid --disable-libuuid --disable-uuidd \
		--disable-fsck --enable-elf-shlibs \
	  && make -j"$J" \
	  && make DESTDIR="$R" install install-libs \
	) >"$L/e2fsprogs.log" 2>&1 && {
		# busybox owns these names as symlinks; the real tools must win.
		for t in mke2fs mkfs.ext2 mkfs.ext3 mkfs.ext4 e2fsck fsck.ext2 \
		         fsck.ext3 fsck.ext4 resize2fs tune2fs dumpe2fs badblocks; do
			[ -L "$R/usr/bin/$t" ] && [ "$(readlink "$R/usr/bin/$t")" = busybox ] \
				&& rm -f "$R/usr/bin/$t"
		done
		( cd "$d" && make DESTDIR="$R" install >/dev/null 2>&1 )
		ok "e2fsprogs"
	} || bad "e2fsprogs (see logs/e2fsprogs.log)"
else
	ok "e2fsprogs already built"
fi

# ----------------------------------------------------------------- dosfstools
step "building dosfstools (mkfs.vfat for the EFI partition)"
if [ ! -x "$R/usr/bin/mkfs.fat" ]; then
	unpack dosfstools-4.2 dosfstools-4.2.tar.gz
	( cd "$W/dosfstools-4.2" && \
	  ./configure --prefix=/usr --sbindir=/usr/bin --enable-compat-symlinks \
		--without-udev \
	  && make -j"$J" \
	) >"$L/dosfstools.log" 2>&1 && {
		for t in mkfs.vfat mkfs.fat mkdosfs fsck.vfat fsck.fat dosfsck; do
			[ -L "$R/usr/bin/$t" ] && rm -f "$R/usr/bin/$t"
		done
		( cd "$W/dosfstools-4.2" && make DESTDIR="$R" install ) >>"$L/dosfstools.log" 2>&1
		ok "dosfstools"
	} || bad "dosfstools (see logs/dosfstools.log)"
else
	ok "dosfstools already built"
fi

# dbus's build needs expat's headers/library. It has never been built by this
# from-source pipeline, but alpm already built and shipped it (same recipe
# the target installs from) - reuse those exact bits into $DEPS/$R instead of
# compiling it a second time.
step "staging expat (dbus's only real dependency)"
if [ ! -f "$DEPS/usr/lib/libexpat.so" ]; then
	pkg=$(ls -t "$B"/repo/*/x86_64/expat-*.alpmz 2>/dev/null | head -1)
	[ -n "$pkg" ] && { tar -xf "$pkg" -C "$DEPS" usr 2>/dev/null; tar -xf "$pkg" -C "$R" usr 2>/dev/null; }
	# The .pc file it ships has prefix=/usr baked in from its own build - real
	# for the target, wrong here, since that makes pkg-config report its libdir
	# as the *host's* /usr/lib rather than this staging tree, no matter where
	# the .pc file itself sits. dbus's meson build resolves expat straight from
	# that reported libdir rather than searching -L paths, so it silently
	# linked the host's own libexpat.so instead ("file in wrong format" - it is
	# not even the same architecture-agnostic format the host linker expected).
	# Repoint it at $DEPS so pkg-config reports the staged copy instead. libdir
	# is its own independent absolute value in this .pc file, not derived from
	# ${prefix} the way includedir is - patching prefix alone still left
	# libdir=/usr/lib untouched, which was the actual value dbus's build used.
	for pc in "$DEPS"/usr/lib/pkgconfig/expat.pc; do
		[ -f "$pc" ] || continue
		sed -i "s|^prefix=/usr|prefix=$DEPS/usr|" "$pc"
		sed -i "s|^libdir=/usr/lib|libdir=$DEPS/usr/lib|" "$pc"
	done
	[ -f "$DEPS/usr/lib/libexpat.so" ] && ok "expat" || bad "expat (no built package in repo/*/x86_64)"
else
	ok "expat already staged"
fi

# ---------------------------------------------------------------------- dbus
# iwd/iwctl link against ell, not libdbus - ell has its own client-side D-Bus
# wire protocol implementation - but that client still has to connect to an
# actual bus, and nothing was ever installed to be one. Plain `iwd &` with no
# bus running is exactly the "failed to initialize dbus" error iwd gives, and
# nothing on the live medium could provide one before this.
step "building dbus 1.16.2 (iwd needs a running system bus, not just a library)"
if [ ! -x "$R/usr/bin/dbus-daemon" ]; then
	unpack dbus-1.16.2 dbus-1.16.2.tar.xz
	( cd "$W/dbus-1.16.2" && \
	  PKG_CONFIG_PATH="$DEPS/usr/lib/pkgconfig" \
	  CFLAGS="$CFLAGS -I$DEPS/usr/include" \
	  LDFLAGS="-L$DEPS/usr/lib" \
	  meson setup build --prefix=/usr --libdir=/usr/lib --sysconfdir=/etc \
		--localstatedir=/var --buildtype=release --wrap-mode=nodownload \
	  && ninja -C build -j"$J" \
	  && DESTDIR="$R" ninja -C build install \
	) >"$L/dbus.log" 2>&1 && ok "dbus" || bad "dbus (see logs/dbus.log)"
else
	ok "dbus already built"
fi

# ------------------------------------------------------------------- ell + iwd
step "building ell 0.83"
if [ ! -f "$DEPS/usr/lib/libell.so" ]; then
	unpack ell-0.83 ell-0.83.tar.xz
	( cd "$W/ell-0.83" && \
	  ./configure --prefix=/usr --libdir=/usr/lib --disable-static \
	  && make -j"$J" \
	  && make DESTDIR="$DEPS" install && make DESTDIR="$R" install \
	) >"$L/ell.log" 2>&1 && ok "ell" || bad "ell (see logs/ell.log)"
else
	ok "ell already built"
fi

step "building libedit (so iwctl links against it instead of GNU readline)"
if [ ! -f "$DEPS/usr/lib/libedit.so" ]; then
	unpack libedit-20260512-3.1 libedit-20260512-3.1.tar.gz
	( cd "$W/libedit-20260512-3.1" && \
	  PKG_CONFIG_PATH="$DEPS/usr/lib/pkgconfig" \
	  CFLAGS="$CFLAGS -I$DEPS/usr/include" \
	  LDFLAGS="-L$DEPS/usr/lib" \
	  ./configure --prefix=/usr --libdir=/usr/lib --disable-static \
	  && make -j"$J" \
	  && make DESTDIR="$DEPS" install && make DESTDIR="$R" install \
	) >"$L/libedit.log" 2>&1 && ok "libedit" || bad "libedit (see logs/libedit.log)"
else
	ok "libedit already built"
fi

# iwctl's configure.ac picks GNU readline unless --enable-libedit is passed, and
# whichever one it picks becomes a hard NEEDED entry in the binary - readline
# has no fallback and Arctic does not ship it (BSD userland: libedit is the
# readline replacement everywhere else too). Left at the default, iwctl links
# against the build host's readline and then fails to start on the target with
# "error while loading shared libraries: libreadline.so.8: cannot open shared
# object file" - the "missing linker error" this fixes.
step "building iwd 3.12 (iwctl - this is what wireless needs)"
if [ ! -x "$R/usr/bin/iwctl" ]; then
	unpack iwd-3.12 iwd-3.12.tar.xz
	( cd "$W/iwd-3.12" && \
	  PKG_CONFIG_PATH="$DEPS/usr/lib/pkgconfig" \
	  CFLAGS="$CFLAGS -I$DEPS/usr/include" \
	  LDFLAGS="-L$DEPS/usr/lib" \
	  ./configure --prefix=/usr --libexecdir=/usr/lib \
		--sysconfdir=/etc --localstatedir=/var \
		--disable-systemd-service --enable-external-ell \
		--enable-libedit \
	  && make -j"$J" \
	  && make DESTDIR="$R" install \
	) >"$L/iwd.log" 2>&1 && {
		# iwd is a daemon and lands in libexec; put it on PATH so the installer
		# and "service start iwd" can just call it.
		[ -f "$R/usr/lib/iwd" ] && ln -sf ../lib/iwd "$R/usr/bin/iwd"
		ok "iwd + iwctl"
	} || bad "iwd (see logs/iwd.log)"
else
	ok "iwd already built"
fi

# -------------------------------------------------------------------- firmware
# The full linux-firmware tree is well over a gigabyte. An installer only needs
# enough to bring a network up, so this takes the wireless drivers plus the GPU
# firmware that stops a console going black.
step "installing wireless firmware"
# The release tarball rather than git: a sparse checkout of linux-firmware needs
# --no-cone for these patterns and the full tree is several gigabytes. An
# installer only needs enough to bring a network up.
FWTAR=$SRC/linux-firmware-20260622.tar.xz
if [ ! -e "$R/usr/lib/firmware/iwlwifi-cc-a0-77.ucode" ] 2>/dev/null; then
	if [ ! -s "$FWTAR" ]; then
		curl -fL --retry 3 -o "$FWTAR" \
			https://cdn.kernel.org/pub/linux/kernel/firmware/linux-firmware-20260622.tar.xz \
			>"$L/firmware.log" 2>&1 || bad "firmware download"
	fi
	if [ -s "$FWTAR" ]; then
		rm -rf "$W/fw"; mkdir -p "$W/fw"
		# Only the wireless drivers people actually hit on a laptop, plus the
		# GPU firmware that keeps a console from going black.
		# Whole vendor directories. 'mediatek/mt76*' looked right but the
		# MT7922 blobs are named mediatek/WIFI_*MT7922*.bin and sit directly in
		# mediatek/, so that pattern silently shipped no MediaTek firmware at
		# all - which is exactly the kind of miss that leaves someone with no
		# wireless. GPU firmware is left out: this is a text installer, and the
		# full linux-firmware is available as a package afterwards.
		tar -xf "$FWTAR" -C "$W/fw" --wildcards \
			'*/intel/iwlwifi/*' '*/iwlwifi-*' \
			'*/ath9k_htc/*' '*/ath10k/*' '*/ath11k/*' '*/ath12k/*' \
			'*/rtw88/*' '*/rtw89/*' '*/rtlwifi/*' \
			'*/brcm/*' '*/mediatek/*' '*/mrvl/*' '*/WHENCE' \
			>>"$L/firmware.log" 2>&1 || :
		d=$(ls -d "$W"/fw/linux-firmware-* 2>/dev/null | head -1)
		if [ -n "$d" ]; then
			# iwlwifi ships every firmware API revision of every device - 180
			# files across 67 devices. The driver loads the newest it supports,
			# so keep the highest revision per device and drop the rest.
			if [ -d "$d/intel/iwlwifi" ]; then
				ls "$d"/intel/iwlwifi/*.ucode 2>/dev/null \
					| sed 's|.*/||; s|-[0-9]*\.ucode$||' | sort -u \
					| while read -r dev; do
					ls "$d"/intel/iwlwifi/"$dev"-*.ucode 2>/dev/null \
						| sort -V | head -n -1 | while read -r old_fw; do
						rm -f "$old_fw"
					done
				done
			fi
			mkdir -p "$R/usr/lib/firmware"
			cp -a "$d"/. "$R/usr/lib/firmware/" 2>/dev/null || :
			n=$(find "$R/usr/lib/firmware" -type f 2>/dev/null | wc -l)
			[ "$n" -gt 50 ] \
				&& ok "firmware ($n files, $(du -sh "$R/usr/lib/firmware" | cut -f1))" \
				|| bad "firmware (only $n files)"
		else bad "firmware (nothing extracted)"; fi
	fi
else
	ok "firmware already installed"
fi

printf '\n\033[1;36m=== USABILITY SUMMARY ===\033[0m\n'
for f in usr/bin/cfdisk usr/bin/sfdisk usr/bin/wipefs usr/bin/mkfs.ext4 \
         usr/bin/mkfs.vfat usr/bin/iwctl usr/bin/iwd usr/bin/lsblk; do
	[ -e "$R/$f" ] && printf '  present  %s\n' "$f" || printf '  MISSING  %s\n' "$f"
done
printf '  firmware %s files\n' "$(find "$R/usr/lib/firmware" -type f 2>/dev/null | wc -l)"
