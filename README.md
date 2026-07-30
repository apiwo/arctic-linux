# Arctic Linux

A Linux distribution built from source, with a BSD userland, glibc, an LLVM
toolchain, busybox init, zsh, doas, and its own package manager.

```
                   .xx
                   xxxx
                  xxxxxx
                 xxxxxxx
                xxxxxxxxx
               .xx ;xxxxxx
               xx   xxxxxxx
              xx+    xxxxxx+
             xxx      xxxxxx
            xxx        xxxxxx
           .xx         ;xxxxxx
           xx           xxxxxxx
          xx+            xxxxxx;
         xxxxxxxxxxxxxxxxxxxxxxx
        xxx                xxxxxx
       .xx                 +xxxxxx
       xx                   xxxxxxx
      xx+                    xxxxxx:
     xxx                      xxxxxx
    xxxx                      xxxxxxx
 xxxxxxxxx;:              :xxxxxxxxxxxxx:
```

## What it is

| | |
|---|---|
| libc | glibc 2.44 — the only GNU component in the system |
| userland | toybox 0BSD (235 commands, static) + busybox for init and networking |
| shell | zsh 5.9.2 |
| init | busybox init, with shell rc scripts and `arctic-service` |
| toolchain | LLVM: clang, lld, libc++ |
| privileges | doas — there is no sudo |
| terminal library | netbsd-curses, not ncurses |
| make / yacc / awk / man | bmake, byacc, the one true awk, mandoc |
| bootloader | Limine, BIOS and UEFI |
| packages | `alpm`, packages are `.alpmz` (tar.xz) |
| kernel | 7.1.3, from the Gentoo dist-kernel config plus an Arctic delta |

### On "no GNU other than glibc"

glibc cannot be compiled by clang — upstream requires GCC — so the build
machines keep a GCC purely as a stage-0 tool for glibc itself. Nothing it
produces beyond glibc is packaged, and the shipped compiler is clang. Every
usual GNU userland component has a non-GNU replacement: coreutils → toybox,
bash → zsh, make → bmake, bison → byacc, gawk → the one true awk, groff/man-db →
mandoc, ncurses → netbsd-curses, sudo → doas, readline → libedit.

## Images

Two profiles, both hybrid BIOS + UEFI, both bootable from a disc or from a USB
stick written with `dd`:

- **Arctic-minimal** — console, the installer, and a copy of the repositories so
  it can install a complete system with no network.
- **Arctic-Live** — the same plus KDE Plasma and a graphical session.

## Installing

You mount the target yourself. Nothing is done behind your back.

```sh
# get online — wired is automatic, for wireless:
iwctl station wlan0 connect YOUR-NETWORK

# partition, then mount the target
mount /dev/nvme0n1p1 /mnt

# the installer opens a configuration menu before it touches anything
arctic-strap /mnt

# then the bootloader
mount /dev/nvme0n1p2 /mnt/boot
arctic-strap boot /mnt/boot     # asks EFI or BIOS

# optionally poke around inside the new system
arctic-chroot

reboot
```

`arctic-strap` asks about network, desktop or window manager, kernel flavour,
user account, root password, locale and keymap, time zone, swap, hostname,
graphics driver, and a handful of extras — then shows you everything for review
before it writes a single file.

Kernel choices are `Arctic-base-kernel` (broad hardware support),
`Arctic-libre-kernel` (no blob loading at all) and `Arctic-small-kernel`
(monolithic, no modules, fast boot).

The first boot of a finished install says hello.

## alpm

```
alpm ins <pkg>              install
alpm ins -s <pkg>           build and install from source
alpm ins -nomod <pkg>       install without putting it into place
alpm commit <pkg>           activate something installed with -nomod
alpm del <pkg>              remove
alpm del+deps <pkg>         remove, and any dependencies left orphaned
alpm del+junk <pkg>         remove, and its config and cache leftovers
alpm del+deps+junk <pkg>    both
alpm get <pkg>              unpack the contents here, install nothing
alpm get -s <pkg>           fetch the upstream source here
alpm fetch all              sync every repository
alpm fetch main extra ...   sync named repositories
alpm add repo <url>         add a repository
alpm list                   what is installed
alpm update                 upgrade the system
```

Plus: `index`, `search`, `info`, `files`, `owns`, `deps`, `rdeps`, `why`,
`orphans`, `stats`, `verify`, `doctor`, `clean`, `hold`, `unhold`, `mark`,
`snapshot`, `rollback`, `log`, `autoremove`, `reins`, `mirror`, `build`.

### Things alpm does that other package managers do not

**`alpm rollback` — undo an install on any filesystem.** Every transaction
saves the files it replaces and records the ones it added, so a bad upgrade is
one command away from being undone. No btrfs, no ZFS, no snapshots layer.

**`alpm ins -nomod` — install without wiring it in.** Lay a kernel down without
touching the bootloader or the initramfs, look at it, then `alpm commit` when
you are ready. Staged packages show up as `s` in `alpm list`.

**`alpm why` — the dependency chain, not just the flag.** Walks upward from a
package to the explicitly-installed thing that dragged it in.

**`alpm doctor` — a real system check.** Broken dependencies, half-finished
transactions, staged packages, orphans, whether a kernel is actually in `/boot`,
whether a bootloader exists, free space — and whether any GNU userland has crept
into `/bin`.

**`alpm verify` — per-file checksums.** Every installed file's sha256 is
recorded, so tampering and bit rot are both detectable, and `alpm reins`
repairs.

**Every nonfree package has a free counterpart.** The `alt-nonfree` repository
mirrors `nonfree` package for package — `nvidia-drivers` ↔ `nouveau-drivers`,
`broadcom-wl` ↔ `b43-open`, `unrar` ↔ `unar` — and they declare conflicts, so
you can swap a proprietary component for a free one and have the package manager
keep you honest.

## Repositories

| repo | what is in it |
|---|---|
| `main` | everything needed to install and boot Arctic |
| `extra` | terminals, editors, fonts, network and dev tools |
| `base` | the bulk: desktops, browsers, media, games, toolchains |
| `kernels` | kernel flavours, headers, firmware |
| `source` | build recipes for every package in every other repo |
| `nonfree` | proprietary firmware and drivers |
| `alt-nonfree` | free replacements for what is in `nonfree` |
| `multilib` | 32-bit libraries, for Steam and Wine |

502 packages are defined in `ports/manifest.tsv`. Recipes are generated from it
by `ports/gen-ports.py`, which keeps per-package data (version, licence,
dependencies, upstream URL) separate from build-system boilerplate.

## Building it yourself

```sh
build-kernel.sh base          # or libre / small
build-rootfs.sh               # glibc, busybox, toybox, zsh, doas, ...
mkpkgs.sh                     # .alpmz packages and repository indexes
iso/mkiso minimal             # or live
```

Sources are fetched from upstream; nothing is vendored.

## Layout

```
alpm/         the package manager: alpm, alpm-build, alpm-repo, libalpm.sh
installer/    arctic-strap, arctic-chroot, and the pure-shell TUI toolkit
skel/         /etc and /usr skeleton: inittab, rc.boot, rc.d, zsh config
ports/        502 package recipes, the manifest, and the generator
branding/     logo, icon theme, wallpapers, boot splash, ascii art
iso/          mkiso and the image profiles
docs/         notes on the design and the build
```

## Status

Arctic-minimal boots and works: Limine → kernel → initramfs → squashfs +
overlay → busybox init → zsh, with `alpm` installing from the repository carried
on the medium. The package manager has been exercised end to end — dependency
resolution, install, upgrade, removal with orphan cleanup, `-nomod` staging and
`commit`, `verify` against a tampered file, and `rollback`.

Arctic-Live's profile is wired up but Plasma is not built yet; that is a long
compile, and `mkiso live` will produce a console-only image until the `base`
repository has been built. `docs/` records what is done and what is not.

## Licence

Arctic's own code (alpm, the installer, the init scripts, the branding) is
BSD-2-Clause. Packaged software keeps its own licence; each recipe states it.
