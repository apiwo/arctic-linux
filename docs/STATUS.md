# What is built, and what is not

Written at the end of the first build so nothing here is overstated.

## Built and verified

- **glibc 2.44** compiled from source, merged-`/usr` layout, C.UTF-8 and
  en_US.UTF-8 locales generated.
- **The userland**: busybox 1.38.0 (400 applets) and toybox 0.8.14 (235
  commands, statically linked), zsh 5.9.2, doas 6.8.2 setuid, libarchive/bsdtar,
  mandoc, the one true awk, bmake, byacc, netbsd-curses, libxcrypt, libmd, zlib,
  xz, zstd. The image is self-contained: no binary in it needs a library from
  the build host.
- **Kernel 7.1.3** from the Gentoo dist-kernel config plus the Arctic delta
  (no BTF/DWARF, no module signing, squashfs/overlayfs/loop/iso9660 and the
  storage and USB controllers in-tree so the initramfs can always find the
  medium). 4811 modules.
- **Arctic-minimal ISO**, 273 MiB, hybrid BIOS + UEFI, boot-tested in QEMU:
  Limine → kernel → initramfs → squashfs + tmpfs overlay → switch_root →
  busybox init → rc.boot → getty → zsh.
- **21 binary packages** (`.alpmz`) in `main` and `kernels`, with repository
  indexes, plus the whole 502-recipe `source` repository. The ISO carries a copy
  of `main`, `kernels` and `source`, so the installer works with no network.
- **alpm**, exercised end to end against a real repository: `fetch`, dependency
  resolution and ordering, `ins`, `reins`, `del`, `del+deps` with orphan
  cleanup, refusing to break dependencies, `ins -nomod` staging and `commit`,
  `verify` detecting a tampered file, `rollback` restoring 1325 replaced files,
  `doctor`, `why`, `owns`, `search`, `stats`.

## Written but not yet exercised

- **arctic-strap** installs onto a mounted target and has been read through, but
  a full install-to-disk run has not been done in this session; the pieces it
  drives (alpm with `--root`, the package set, fstab and bootloader writing) have
  been tested individually. Configuring and installing are two separate tools
  now - `arctic-conf`/`arctic-boot-conf` only ask questions and save an answer
  file, `arctic-strap`/`arctic-boot-strap` only do the work, non-interactively,
  from whatever was last saved.
- **There is no desktop image, by design.** Arctic ships one ISO that boots to a
  TTY running zsh. Desktop packages exist as recipes in `base` for anyone who
  wants to install one afterwards, but no graphical image is built or shipped.
- **481 of the 502 recipes** have never been run. They are generated from the
  manifest against build-system templates, so the shape is right and the
  metadata is real, but expect the usual per-package friction on first build.
- The `Arctic-libre-kernel`, `Arctic-small-kernel`, `Arctic-rt-kernel`,
  `Arctic-lts-kernel` and `Arctic-hardened-kernel` recipes exist; only
  `Arctic-base-kernel` has been compiled.

## NVIDIA proprietary driver

Verified, not assumed. `readelf -d` on a real installed driver shows the whole
stack needs only glibc, X/wayland libs, and two GNU runtime libraries:

    libnvidia-api.so.1     NEEDED libstdc++.so.6
    libnvidia-rtcore.so    NEEDED libgcc_s.so.1

Arctic now builds and ships those two (package `gcc-libs`, runtime only - not
the compiler), GNU make as `gmake` for kbuild, and `libglvnd` so NVIDIA GL and
mesa can coexist. The proof:

    $ ld-linux --library-path <arctic>/usr/lib --list libnvidia-api.so.1
    libnvidia-api.so.1               missing=0   resolved-from-arctic=6
    libnvidia-rtcore.so.610.43.03    missing=0   resolved-from-arctic=6
    libnvidia-glcore.so.610.43.03    missing=0   resolved-from-arctic=6
    nvidia-smi                       missing=0   resolved-from-arctic=6

Every dependency of the real driver resolves against Arctic's libraries with
nothing missing, and `libstdc++`/`libgcc_s` come from Arctic's own build.
`/usr/bin/make` is still bmake; the userland is unchanged.

## Builds are sandboxed now

`build/arctic-sandbox` runs every build under bubblewrap with the host
bind-mounted read-only. `arctic-sandbox --check` proves it, including that
writing to `/usr/lib/libc.so.6` is refused. `build-rootfs.sh`, `build-kernel.sh`
and `mkpkgs.sh` refuse to start unless `ARCTIC_SANDBOX=1`. This is not optional
politeness - see bug 10.

## Source URL health

`build/check-sources.sh` verifies every manifest URL in parallel;
`build/fix-versions.py` resolves the failures against upstream tags and
directory listings. Currently **415 of 479 resolve**, up from 359. The remaining
64 are versions I could not determine automatically and are listed in
`arctic-build/logs/sources/bad`.

The resolver refuses to accept a fix that drops a major version - a truncated
listing had it downgrade chromium to 101 and blender to 2.82 before that guard
existed. Package versions in `base` are best-effort until each one is built.

## Binary packages

**69 packages are built as binaries**: 51 in `main`, 11 in `extra`, 3 in
`kernels`, 4 in `profile`. 43 of them pass full verification - installed into a
clean root, every claimed file present, checksums confirmed, every ELF resolved,
removed cleanly again. The other 4 fail only because they declare a dependency
that is still source-only (`iproute2` wants `libcap`, `iwd` wants `dbus`,
`pcre2` wants `bzip2`), which is the correct thing for them to do.

Everything else in the 520-package manifest stays **source-only on purpose**.
Asking for one now gives:

    WARN: This package has no binary. Proceed to compile Y/n?

Enter accepts, `n` skips it and carries on with the rest, and a genuine typo
still fails outright. Building the whole manifest is not a matter of patience -
Chromium, Firefox, Qt6, KDE and LLVM are days of compute between them.

Still source-only after the batch run, with the reason:

    bzip2         Makefile has no DESTDIR (hand-written recipe added, untested)
    libcap        builds Go helpers that fail without a Go toolchain
    curl/openssl  need a TLS backend selected explicitly
    tmux          does not find libevent in the staging prefix
    lua, json-c, wireless-regdb, nftables, vim

## Fixes from the first real install attempt

Someone actually booted it and tried to install. Everything below came out of
that, and every one of them would have blocked a real install:

1. **The menu flickered on every keypress.** Each navigation redrew the entire
   screen, including a full `ESC[2J` clear - visibly unpleasant on a VGA
   console. The menu, checklist and text input now draw once and repaint only
   the rows that changed. Measured: one clear for a whole interaction instead of
   one per key.

2. **`mount /dev/sdb1 /mnt` failed** because there was nothing to mount. busybox
   provides `mke2fs` but it only makes **ext2**, so `mkfs.ext4` did not exist and
   neither did `cfdisk`, `sfdisk` or `wipefs`. The image now ships util-linux,
   e2fsprogs and dosfstools, and `arctic-strap` has a disk step that will
   partition, format and mount the target for you.

3. **The boot status column wrapped**, showing `[ OK` on one line and `]` on the
   next. The padding was computed one character too wide: the `  :: ` prefix is
   5 columns and `[  ok  ]` is 8, so the pad has to be `cols - len - 13`, not
   `- 12`. It also read the width from `stty` on a non-terminal during early
   boot and got nothing.

4. **No `iwctl`, and no firmware at all**, so wireless could never have worked.
   iwd, ell and the wireless firmware are now on the image.

5. **`alpm fetch all` reported "554 packages available" while every repository
   was unreachable.** It counted the cached index and called that success. It
   now reports what was actually reached, and says plainly when nothing was.

6. **The medium's own `file://` repositories never worked.** There is no curl on
   the ISO and busybox wget rejects the scheme outright, so the offline install
   could not read the packages on the disc it booted from. alpm now handles
   `file://` itself with a copy.

7. **The MediaTek firmware was silently missing.** The extraction pattern was
   `mediatek/mt76*`, but the MT7922 blobs are `mediatek/WIFI_*MT7922*.bin` in
   the top of `mediatek/`, so no MediaTek firmware shipped at all - on a machine
   whose wireless card is an MT7922.

## Fixes from the second real install attempt

Fix 2 above shipped real `cfdisk`, `sfdisk`, `wipefs` and `lsblk` binaries, but
`build-usable.sh` built them the way a native, non-cross build on this host
naturally comes out - and that quietly linked several of them against the build
host's own libraries instead of Arctic's. Booting the result reproduced almost
the same failure the fix was supposed to solve, plus a new one in `iwctl`.

1. **`cfdisk` and `lsblk` printed "This is a wrapper script" instead of
   running, and most of the rest of the disk toolkit (`sfdisk`, `wipefs`,
   `blkid`, `findmnt`, `partx`, `mkswap`, `swapon`, `swapoff`, `losetup`) did
   nothing at all.** libtool leaves the real binary at `.libs/$t` and puts a
   "temporary wrapper script ... should never be moved out of the build
   directory" at the top-level `$t` - `build-usable.sh` was copying the
   wrapper. It now copies `.libs/$t`.

2. **`cfdisk` and `lsblk` then failed with `error while loading shared
   libraries: libncursesw.so.6` / `libtinfow.so.6: cannot open shared object
   file`.** With the wrapper-script bug fixed, the real binaries turned out to
   be linked against the build host's GNU ncurses - Arctic ships netbsd-curses
   and none of that. Getting util-linux to build against netbsd-curses instead
   took three separate fixes, each a different tool finding the host's copy of
   something by a different route:
   - `PKG_CONFIG_PATH`, `CFLAGS` and `LDFLAGS` now point at `$DEPS`, Arctic's
     staging prefix, so `-lncursesw` resolves to netbsd-curses.
   - util-linux's ncurses probe tries `ncursesw6-config` *before* pkg-config,
     and this host has one; it was handing back the host's own
     `-I/usr/include/ncursesw` regardless of `PKG_CONFIG_PATH`, so header and
     library came from two different curses implementations that disagree on
     how globals like `acs_map` are exposed. `NCURSESW6_CONFIG=false` (and the
     5-config/non-w variants) forces the probe to fall through to pkg-config.
   - netbsd-curses' own install only provided `libtinfo.so`/`tinfo.pc`, not
     the wide-char `libtinfow.so`/`tinfow.pc` name that the same probe tries
     first, so *that* lookup alone still fell through to the host. Both are
     now aliased in `build-rootfs.sh` alongside the existing ncurses symlinks.
   - GNU-ncurses-style packages also expect headers under an `ncursesw/`
     subdirectory that netbsd-curses doesn't have; `build-rootfs.sh` now
     shims one that redirects back to Arctic's own flat headers.

3. **`iwctl` failed with `error while loading shared libraries:
   libreadline.so.8: cannot open shared object file`.** Left to its own
   defaults, iwd's client links GNU readline for line editing, and Arctic
   ships none. iwd also supports `--enable-libedit` as a drop-in alternative;
   `build-usable.sh` now builds libedit first and passes that flag. util-linux
   hit the same readline issue in `sfdisk`/`fdisk`'s interactive prompt, but
   has no libedit option there, so that build now passes `--without-readline`
   instead.

Verified by booting the rebuilt image in QEMU and running `lsblk`, `cfdisk
--version`, `sfdisk --version` and `iwctl --version` for real, plus checking
every `NEEDED` entry of every shipped binary against what the rootfs actually
ships - nothing points outside it.

## Bugs found and fixed while building

Kept because each one is a trap worth remembering.

1. **Pointing the host linker at the target glibc.** `-L$ROOTFS/usr/lib` in a
   native build makes the host linker try to link host objects against the
   freshly built libc: *"file in wrong format"*. Libraries we build and then
   link against now go to a separate staging prefix that contains no libc.

2. **`pgrep -x <name>` cannot detect a daemon from a service script of the same
   name.** The kernel sets `comm` to the basename of the *script* being
   interpreted, so `/etc/rc.d/bluetoothd` matched itself and every service
   reported "running". Service detection now compares `/proc/*/exe`.

3. **Recursion without `local`.** `_resolve` in alpm shared `pkg` and `deps`
   with its own recursive calls, so the name appended to the install order was
   whatever the deepest call left behind — duplicated and wrong packages.

4. **Writing through a symlink.** mkiso created a convenience script at
   `/usr/bin/install`, which is a symlink to the toybox multiplexer — so the
   redirect replaced the toybox *binary* with a three-line script that started
   an interactive shell. Every toybox command then hung, `rc.lib` hung on `cut`,
   and the boot never finished. Renamed, and mkiso now unlinks before writing.

5. **An empty `/dev` after `switch_root` makes a failing boot silent.** PID 1
   opens `/dev/console` for all of its output. The initramfs now moves its
   devtmpfs into the new root, and the image ships real `console`, `null`, `tty`
   nodes as a fallback.

6. **`rc.boot` mounting a tmpfs on `/run` hid the medium**, and with it the
   offline repository. The initramfs now mounts `/run` before moving the medium
   into it, so `rc.boot` leaves it alone.

7. **glibc 2.44 no longer ships libcrypt**, so `doas` and `login` had no
   `crypt()`. libxcrypt is now built — with the default soname (`libcrypt.so.2`),
   not the glibc-compatibility `libcrypt.so.1`.

8. **`ldd` is a bash script** and Arctic has no bash; `getconf` is toybox's and
   does not know `GNU_LIBC_VERSION`. Arctic ships its own POSIX `ldd` that asks
   the dynamic loader, and records the libc version in `/etc/arctic-release`.

9. **`mkiso` seeded the package index after the squashfs was already packed**,
   so `/var/lib/alpm/sync` was empty on the booted image and `alpm info` could
   not find anything until you ran `alpm fetch`. Order matters: anything writing
   into the squashfs source tree has to happen before `mksquashfs`.

10. **`rm -rf` into a live bind mount.** A chroot session left `/proc`, `/sys`
   and `/dev` bound under the ISO work tree; the next build's `rm -rf` walked
   into the host's `/dev` and emptied it. mkiso now refuses to delete a work
   tree with anything mounted under it.

11. **A `make install` without `DESTDIR` replaced the host's glibc.** Arctic's
    glibc is configured `slibdir=/usr/lib`, so it installed 2.44 over the host's
    2.43 and every dynamically linked binary on the machine died with
    `undefined symbol: __pointer_chk_guard`. The login shell included, so there
    was no way to run a repair from inside. This is why builds are sandboxed
    now, and why a static busybox is worth keeping around - it was the only
    thing that still ran.

## Installer split, and a networking bug that made DHCP a no-op

`arctic-strap` used to ask every question and then install, in one run. It is
now two tools each, on purpose: `arctic-conf`/`arctic-boot-conf` only ask
questions and save an answer file; `arctic-strap`/`arctic-boot-strap` only do
the work, non-interactively, from whatever was last saved (or from built-in
defaults, if nothing was - the same way `pacstrap` does not ask you anything
either). `arctic-conf`'s menus picked up real fixes along the way, not just
the split:

1. **The filesystem menu rendered as `ext4` / `Its` / `really` / `fast` -
   each word of the description on its own broken row.** Several menus built
   their item list by concatenating `items="$items key|label|description"`
   and then expanding `$items` unquoted. Shell word-splitting does not know
   about the `|` fields; it splits on every space, so any description longer
   than one word became several separate (broken) menu entries - the wireless
   network list, the disk list, the swap-partition list and the timezone
   region list all had the same bug, not just the filesystem one. Fixed by
   building each list with `set -- "$@" "item"` instead, which POSIX sh never
   word-splits. The filesystem menu additionally lost its descriptions
   entirely rather than relying on every future edit remembering to quote
   correctly, and grew from 4 choices to 7: ext4, btrfs, xfs, f2fs, ext3,
   ext2, and zfs (gated on `have zpool` - Arctic has no zfs-utils package yet,
   so this one is plumbing for later, not a tested path).
2. **DHCP obtained a lease and then configured nothing at all.** `udhcpc`
   only speaks the DHCP protocol; a `-s script` is what actually applies the
   lease (sets the address, the default route, `/etc/resolv.conf`), and
   Arctic had never shipped one - not on the ISO, not on an install, not in
   the installer's own network screens. Every DHCP-based network, wired or
   wireless, looked like it came up and never actually worked. Added
   `/usr/share/udhcpc/default.script` (matching busybox's own compiled-in
   default path) and pass `-s` explicitly wherever `udhcpc` is invoked.
3. **A wifi-only install could bring up the wrong interface on first boot.**
   `arctic-conf` never recorded which wireless device it associated on, so
   `rc.d/network`'s `pick_iface()` fell through to "whatever is first" on a
   machine with more than one interface. Now saved as `A_WIFI_IFACE` /
   `NET_IFACE`.
4. **A file placed anywhere under `skel/usr` other than `skel/usr/bin` was
   silently missing from every real install**, though present on the live
   ISO - `mkpkgs.sh`'s arctic-base packaging step only copied `skel/usr/bin`,
   while `mkiso` copies all of `skel/usr`. Found via the udhcpc script above,
   which lives at `skel/usr/share/udhcpc/`. Both now copy the whole tree.

The btrfs-snapshot request that prompted a look at all this - a checkpoint
before every package install/removal, timeshift or snapper, user's choice -
turned out to already be built: `alpm`'s `tx_snapshot()` calls
`arctic-snapshot create` before every transaction when `/` is btrfs, and
`arctic-snapshot` (shipped in arctic-base) delegates to timeshift or snapper
per `/etc/arctic/snapshot.conf`'s `TOOL=`, falling back to driving btrfs
subvolume snapshots directly when neither is installed. `arctic-conf`'s
filesystem screen already writes that config when btrfs is chosen. Nothing
new was needed there, only confirmed end to end.

Boot-testing the new split (in QEMU, with an attached blank disk) caught one
more, unrelated to any of the above and much nastier: **`alpm ins` of more
than two or three packages corrupted the entire screen**, the download
progress bar's percentage climbing to absurd values like `2350%` and
`213700%` and its fill string growing long enough to wrap and repeat down the
whole terminal. `libalpm.sh`'s `bar()` used a plain `i` for its own fill-loop
counter - and so does the package-fetch loop in `alpm`'s `cmd_ins` that calls
it (`for p in $todo; do i=$((i+1)); bar "$i" "$n" "$p"; ...; done`). POSIX sh
has no real variable scoping, so they were the same variable: each call to
`bar()` ran its drawing loop up to `$width` and left the caller's `i` sitting
there instead of at the package index, so the *next* call computed its
percentage from that leaked value instead of the real one - growing further
out of bounds with every package in the transaction. Exactly the same class
of bug as "recursion without local" above, in a function that bug had not
reached. Fixed by prefixing every variable `bar()` touches with `_bar_`, so
it can no longer collide with whatever a caller happens to also call `i`.
Verified by installing an 8-package transaction and watching the bar reach a
clean `100%` instead.

## A second bug-hunting pass

Asked for another pass after the above, specifically over the new installer
split and anything of the same shape. Audited every shared function in
`alpm`/`libalpm.sh`/`alpm-build`/`alpm-repo` for the `bar()`-style unscoped-
variable collision (nothing else was found - `bar()` really was the one)
and re-read the four new installer scripts and the service layer they call
into. Five more real bugs, all fixed and re-verified live:

1. **`arctic-boot-strap /mnt/boot --efi` silently ignored `--efi`.** The
   documented (and requested) calling convention puts the path before the
   flag, but the argument-parsing loop `break`-ed out on the first non-flag
   token, so it never looked at anything after the path. Rewrote the loop to
   pick out the first non-flag argument as BOOTDIR while continuing to scan
   the rest for flags, so either order works. Gave `arctic-strap` the same
   treatment for `-f`/`-c` - it happened to match its own documented
   flags-first usage so wasn't broken yet, but a user typing the target
   first would have hit the identical trap.
2. **A password or wifi passphrase containing an apostrophe corrupted the
   saved answer file and silently emptied itself.** `save_conf` (and
   `arctic-boot-conf`'s config write) built the file with
   `A_USERPASS='$A_USERPASS'`-style heredoc interpolation; a literal `'` in
   the value closes the quote early and breaks every line after it, which
   `arctic-strap` then fails to source at all. Added a `shq()` helper
   (replace `'` with `'\''`) and quote every interpolated value through it.
3. **A service running without a pidfile could never actually be stopped.**
   `svc_running()` has a fallback that finds a daemon by scanning
   `/proc/*/exe` when there is no pidfile (started outside `svc_start`, or
   the pidfile was lost) - but `svc_stop()` only ever tried to read a PID
   from the pidfile, so in exactly that situation it reported the service
   as running and then did nothing. Gave `svc_stop()` the same `/proc/*/exe`
   fallback.
4. **`rc.d/pipewire status` reported "running" unconditionally**, the same
   bug already documented and fixed elsewhere in this file
   ("`pgrep -x <name>` cannot detect a daemon from a service script of the
   same name") - just not applied here, since this script is a standalone
   case statement rather than a `svc.lib` user. A script named `pipewire`
   gets `comm=pipewire` while it runs, so its own `pgrep -x pipewire` check
   matched itself. Switched to the same `/proc/*/exe` comparison
   `svc_running` uses.
5. **A failure in `hostname -F /etc/hostname` silently renamed the machine
   to the literal string `arctic`.** `[ -f /etc/hostname ] && hostname -F
   /etc/hostname || hostname arctic` is the classic `A && B || C` trap: if
   `A` is true and `B` fails for any reason unrelated to the file's
   existence, `C` runs too. Replaced with an actual if/then/else, with a
   second, more direct attempt before giving up.

Every other `A && B || C` occurrence in the tree was checked and left alone:
they are all the safe ternary shape, where the middle command is a plain
`echo`/`printf`/assignment that cannot itself fail for an unrelated reason.

Verified live: `arctic-boot-strap /tmp/fakeboot --efi` now reaches "no
kernel image found" (past argument parsing, exactly where a bad target
should fail) instead of silently defaulting away from `--efi`, and
`/etc/rc.d/pipewire status` now correctly exits 1 on a fresh boot instead of
always exiting 0.

## Disk encryption, a real initramfs, and Slackware-style package selection

`arctic-conf` now offers full-disk LUKS2 encryption as a step in the disk
screen, plus two new steps: a fonts checklist and a Slackware-style extra
package browser split into nine categories (terminals, editors, browsers,
media, developer tools, virtualisation, gaming, CLI utilities, office).

Getting encryption to actually boot needed three separate pieces that did
not exist before:

1. **`arctic-mkinitramfs`** (`skel/usr/bin/arctic-mkinitramfs`) did not
   exist at all, despite being referenced from four call sites (alpm's
   post-kernel-install hook, the NVIDIA driver install hook, and
   `arctic-strap`). Arctic's kernel builds its storage/filesystem/USB
   drivers directly in rather than as modules, so a plain unencrypted
   install never needed an initramfs and the gap went unnoticed - but an
   encrypted root needs a passphrase prompt before anything else can run,
   and dm-crypt is one of the few things this kernel does build as a
   module. Wrote it: busybox-based, bundles cryptsetup plus every
   `kernel/crypto/*.ko` and `kernel/drivers/md/dm-*.ko` (~5 MiB) only when
   `/etc/crypttab` has a real entry, resolves shared library dependencies
   with Arctic's own `ldd`, and generates an `/init` that parses
   `rd.luks.uuid=`/`cryptdevice=` off the kernel command line, retries the
   passphrase up to 5 times, then `switch_root`s.
2. **`cryptsetup` could not actually run.** It builds fine, but
   `readelf -d` on the real binary showed a `libpopt.so.0` dependency that
   nothing in the manifest provided - popt was never packaged anywhere in
   Arctic. Exactly the same class of bug as the native-build-links-against-
   the-host issue fixed earlier for iwctl/cfdisk, just caught this time
   before it shipped rather than after. Added `popt` as its own port,
   built it, added it to cryptsetup's `depend=`, and rebuilt cryptsetup.
   Verified for real, not just by name-matching: extracted both packages,
   ran `usr/sbin/cryptsetup --version` through Arctic's own dynamic linker
   with only the staged libraries on `--library-path`, then did a full
   `luksFormat` → `open` → `status` → `close` cycle against a loopback
   file, including confirming a wrong passphrase is correctly rejected.
3. **cryptsetup was not available during the live install session at
   all** - only `target_alpm` (chrooted, for the just-installed system)
   existed as a way to pull it from the bundled repo; the live-session
   partitioning code that actually calls `cryptsetup luksFormat` had no
   equivalent and would have just failed with "cryptsetup is not on this
   image" on every real ISO. Added `ensure_cryptsetup()`, which
   self-installs it live via `alpm ins cryptsetup` (same `file://` medium
   repo `target_alpm` already uses, just without a chroot) before falling
   back to that error.

The `A_ENCRYPT`/`A_FONTS`/`A_PKGS` answers all round-trip through
`save_conf`'s `shq()`-quoted format and are installed by `arctic-strap` via
`target_alpm`, the same path every other package selection already used.
`arctic-boot-strap` reads the LUKS UUID back out of the installed
`/etc/crypttab` and prepends `rd.luks.uuid=` to every kernel command line it
writes, for both Limine and GRUB.

Also renamed `arctic-service` to `service` throughout (script itself,
`README.md`, `iso/mkiso`, `build/build-usable.sh`, `skel/etc/inittab`,
`skel/etc/arctic/rc.lib`, `skel/etc/zsh/zshrc`, `skel/etc/rc.d/fstrim`,
`skel/usr/bin/arctic-firstboot`) - shorter, and nothing else on the system
uses the `arctic-` prefix for a command a user types directly.

One regeneration hazard found and closed while adding the `popt` port:
running `ports/gen-ports.py` after a manifest edit silently overwrote
`ports/extra/tmux/recipe`'s hand-fix (staged `CPPFLAGS`/`LDFLAGS`/
`PKG_CONFIG_PATH` pointing at the Arctic deps prefix instead of the host's),
because it had never been given a `recipe.local` marker. Restored it and
added the marker. `cryptsetup` and `json-c` already had theirs from earlier
fixes and were correctly left alone by the same regeneration.

## Known rough edges

- `alpm rollback` restores files but does not fully reconcile the package
  database for packages it resurrects; `alpm doctor` correctly reports the
  resulting unsatisfied dependency rather than hiding it.
- The `source` repo's index reports zero sizes, since nothing has been built
  from most recipes yet.
- `arcticfetch` reports the terminal as empty on a bare console, which is
  correct but looks odd.
- `btrfs-progs`/`xfsprogs`/`f2fs-tools` are not baked into the live rootfs
  the way `e2fsprogs`/`dosfstools` are (see `build/build-usable.sh`) - only
  built as installable `.alpmz` packages. `arctic-conf`'s filesystem screen
  already guards this correctly (`have mkfs.btrfs && ...` only lists a
  filesystem if the live session can actually format it), so picking one of
  these on a real ISO today just means it will not appear in the menu at
  all rather than failing partway through. Giving the live session the same
  `ensure_cryptsetup()`-style self-install (`alpm ins btrfs-progs` etc.
  before the `have` check) rather than only listing what already happens to
  be on the medium would close this the same way it was closed for
  cryptsetup.
- Disk encryption has been verified at the binary level (a real
  `luksFormat`/`open`/`close` cycle against a loopback file with both the
  right and a wrong passphrase) and the generated initramfs `/init` has
  been read through and syntax-checked, but a full interactive
  `arctic-conf` → `arctic-strap` → reboot → passphrase-prompt run in QEMU
  has not been done in this session.
