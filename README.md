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
| libc | glibc 2.44 |
| userland | toybox 0BSD (235 commands, static) + busybox for init and networking |
| shell | zsh 5.9.2 |
| init | busybox init, with shell rc scripts and `arctic-service` |
| toolchain | LLVM: clang, lld, libc++ |
| privileges | doas — there is no sudo |
| terminal library | netbsd-curses, not ncurses |
| make / yacc / awk / man | bmake, byacc, the one true awk, mandoc |
| GPU | NVIDIA proprietary, AMD and Intel via mesa, all coexisting through libglvnd |
| bootloader | Limine, BIOS and UEFI |
| packages | `alpm`; packages are `.alpmz` — **A**rctic **L**inux **P**ackage **M**anagement **Z**ip (a tar.xz) |
| kernel | 7.1.3, from the Gentoo dist-kernel config plus an Arctic delta |

### On GNU components

The goal is a BSD userland, and that holds: coreutils → toybox, bash → zsh,
make → bmake, bison → byacc, gawk → the one true awk, groff/man-db → mandoc,
ncurses → netbsd-curses, sudo → doas, readline → libedit. None of those are GNU.

Four GNU pieces are shipped, each for a reason that cannot be engineered away:

| component | why |
|---|---|
| **glibc** | the C library. Also the only libc the NVIDIA driver supports. |
| **libstdc++** | `libnvidia-api.so.1` links against `libstdc++.so.6`. libc++ is not ABI-compatible and the blob cannot be relinked. |
| **libgcc_s** | `libnvidia-rtcore.so` (OptiX / RT cores) links against `libgcc_s.so.1`. |
| **GNU make** | Linux's kbuild is written against GNU make; bmake cannot drive it, so out-of-tree kernel modules need it. Installed as `gmake` — `/usr/bin/make` is still bmake. |

These were not assumed. They were read straight off a real installed NVIDIA
driver with `readelf -d`, and `gcc-libs` ships **only** those two runtime
libraries — not the compiler. Arctic still compiles with clang.

glibc additionally cannot be compiled by clang (upstream requires GCC), so the
build machines keep a GCC as a stage-0 tool. It is not packaged.

### NVIDIA proprietary driver

Supported, and the package set reflects what the driver actually needs:

    nvidia-drivers → glibc gcc-libs libglvnd libx11 libxext libxxf86vm
                     libdrm wayland mesa libpciaccess
    built with     → gmake linux-headers clang

`libglvnd` is what lets the NVIDIA GL implementation and mesa coexist, so an
NVIDIA machine and an AMD/Intel machine can run the same image. Choosing
`nvidia` in the installer pulls all of this in automatically. If you would
rather not run a blob, `alt-nonfree` has `nouveau-drivers` as a drop-in
counterpart, and they declare a conflict so you cannot install both.

## The image

One image: **Arctic-minimal**. Hybrid BIOS + UEFI, boots from a disc or from a
USB stick written with `dd`.

It boots to a TTY running **zsh**. No display manager, no desktop, and no bash
anywhere in the tree — `/bin/sh` is busybox ash and the login shell is zsh. It
carries a copy of the repositories, so it can install a complete system with no
network.

A desktop is something you install afterwards, with `alpm`.

## Installing

You mount the target yourself. Nothing is done behind your back.

Configuring and installing are two separate tools, on purpose: the `-conf`
ones only ask questions and write an answer file, the plain ones only do the
work, non-interactively, from whatever was last answered.

```sh
# get online — wired is automatic, for wireless:
iwctl station wlan0 connect YOUR-NETWORK

# partition, then mount the target
mount /dev/nvme0n1p1 /mnt

# arctic-conf opens a configuration menu and writes the answers; arctic-strap
# does the actual install from them, no menus, no questions
arctic-conf /mnt
arctic-strap /mnt

# same split for the bootloader
mount /dev/nvme0n1p2 /mnt/boot
arctic-boot-conf /mnt/boot
arctic-boot-strap /mnt/boot --efi     # or --bios [--loader=grub]

# optionally poke around inside the new system
arctic-chroot

reboot
```

`arctic-conf` asks about network, desktop or window manager, kernel flavour,
user account, root password, locale and keymap, time zone, swap, hostname,
graphics driver, and a handful of extras — then shows you everything for review
before it saves a single file. `arctic-strap` takes that answer file and
installs; run it alone (no `arctic-conf` first) and it installs a console-only
system with sane defaults, the same way `pacstrap` does not ask you anything
either.

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

## Profile packages

A profile is not an ordinary package. Installing `niri-dms` does not give you a
bare compositor — it pulls in the whole set and writes the configuration, so you
get a working desktop rather than a starting point. alpm says so before it
touches anything:

```
WARNING: This is a profile package it installs more than one package and
configures it rather than being a basic installation.
```

| profile | what you get |
|---|---|
| `niri-dms` | niri + DankMaterialShell, the neutral grey/white rice, foot, fuzzel, mako, and the sway-style keybinds (Mod+Return terminal, Mod+D launcher, Mod+Shift+Q close) |
| `arctic-kde` | KDE Plasma with foot as the terminal and the Arctic colour scheme |
| `arctic-xfce` | Xfce with the Arctic theme, foot, and a neutral panel |
| `apiwow-dwm` | dwm + picom + slstatus in a calm grey and white scheme, JetBrainsMono throughout |

Config files are marked `backup=`, so alpm will not overwrite yours on upgrade,
and anything a profile does replace is recoverable with `alpm rollback`.

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
| `profile` | riced setups: install one and get a whole configured desktop |
| `multilib` | 32-bit libraries, for Steam and Wine |

502 packages are defined in `ports/manifest.tsv`. Recipes are generated from it
by `ports/gen-ports.py`, which keeps per-package data (version, licence,
dependencies, upstream URL) separate from build-system boilerplate.

## Building it yourself

**Every build runs in a sandbox, and the scripts refuse to start without one.**

Arctic's glibc is configured with `slibdir=/usr/lib` so the target gets a
merged-`/usr` layout. A recipe that forgets `DESTDIR` would therefore install
that glibc straight over the *host's* `/usr/lib` and break every binary on the
machine. That is not hypothetical — it happened once during development. So the
host filesystem is now mounted read-only for all builds, and a stray install
fails with `EROFS` instead of taking the machine down.

```sh
build/arctic-sandbox --check          # prove the sandbox holds, first

build/build.sh                        # fetch, kernel, rootfs, tools, package, ISO
```

It uses bubblewrap: the whole host is bind-mounted read-only, and only the build
tree, the source tree and `/tmp` are writable. Sources are fetched from upstream;
nothing is vendored.

Bubblewrap is not a hard requirement of Arctic itself, only of building safely.
A host without it (no unprivileged user namespaces, a container that can't
nest one) can still build by setting `ARCTIC_UNSANDBOXED=i-accept-the-risk` -
`build/arctic-sandbox` warns loudly and then runs with no isolation at all.
Do this only if you understand that a recipe forgetting `DESTDIR` can then
overwrite your own machine's libc, which is exactly what happened once. When
bubblewrap is available, use it.

## Layout

```
alpm/         the package manager: alpm, alpm-build, alpm-repo, libalpm.sh
installer/    arctic-conf/-strap, arctic-boot-conf/-strap, arctic-chroot,
              and the pure-shell TUI toolkit
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

There is deliberately no desktop image. Arctic boots to a TTY and you build up
from there. `docs/STATUS.md` records what is done and what is not.

## Licence

Arctic's own code (alpm, the installer, the init scripts, the branding) is
BSD-2-Clause. Packaged software keeps its own licence; each recipe states it.
