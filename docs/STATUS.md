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
  been tested individually.
- **Arctic-Live** — the profile, package list and SDDM/Plasma theming exist.
  Plasma itself is not built. `mkiso live` currently produces a console image
  with a manifest of what it expects. Building `base` is a many-hour compile.
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

## Known rough edges

- `alpm rollback` restores files but does not fully reconcile the package
  database for packages it resurrects; `alpm doctor` correctly reports the
  resulting unsatisfied dependency rather than hiding it.
- The `source` repo's index reports zero sizes, since nothing has been built
  from most recipes yet.
- `arcticfetch` reports the terminal as empty on a bare console, which is
  correct but looks odd.
