# Building Arctic Linux

These are the scripts that produced the images. They expect a Linux host with a
working C toolchain, `cmake`, `ninja`, `xorriso`, `mksquashfs` and about 30 GiB
free. Paths default to `/home/apiwo/arctic-build`; override with `ARCTIC_BUILD`
where the scripts honour it, or edit `B=` at the top.

```sh
./fetch.sh              # download every upstream tarball named in sources.list
./build-kernel.sh base  # or: libre / small
./build-rootfs.sh       # glibc, busybox, toybox, zsh, doas, and the rest
./mkpkgs.sh             # turn the results into .alpmz and index the repos
../iso/mkiso minimal    # or: live
```

Each step is idempotent: anything already built is skipped, so a failed run can
be fixed and re-run without starting over.

## A note on the toolchain

Arctic ships LLVM. glibc, however, cannot be compiled by clang — upstream
requires GCC — so `build-rootfs.sh` uses the host's GCC as a stage-0 tool for
glibc alone. Nothing it produces beyond glibc is packaged.

This is a *native* build, so every compiler invoked is the host's. The one thing
that must never happen is putting the target `usr/lib` on the linker's search
path: the host linker then tries to link host objects against the freshly built
libc and fails with "file in wrong format". Libraries Arctic builds and then
links against go into a separate staging prefix under `stage/deps`, which
contains no libc and is therefore safe on `-L`.
