#!/bin/sh
# build.sh - build all of Arctic Linux, start to finish.
#
#   build/build.sh                run the whole pipeline
#   build/build.sh rootfs iso      run only these steps
#
# Steps, in order: fetch, kernel, rootfs, usable (the disk/wireless tools
# layered on top - see docs/STATUS.md), pkgs (package everything into
# .alpmz and index the repos), iso (master the bootable image).
#
# Every step that touches the filesystem runs through arctic-sandbox, so this
# script does not need ARCTIC_SANDBOX set and should not be run inside one
# itself. Each underlying step is idempotent - already-built pieces are
# skipped - so a failed run can be fixed and re-run without starting over.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TREE=$(dirname -- "$HERE")
SANDBOX="$HERE/arctic-sandbox"

step() { printf '\n\033[1;35m== %s ==\033[0m\n' "$*"; }

do_fetch()   { step "fetch sources"; ( cd "$HERE" && ./fetch.sh ); }
do_kernel()  { step "kernel";  "$SANDBOX" "$HERE/build-kernel.sh" "${KERNEL_FLAVOR:-base}"; }
do_rootfs()  { step "rootfs";  "$SANDBOX" "$HERE/build-rootfs.sh"; }
do_usable()  { step "usable tools (disk, wireless)"; "$SANDBOX" "$HERE/build-usable.sh"; }
do_pkgs()    { step "package + index";  "$SANDBOX" "$HERE/mkpkgs.sh"; }
do_iso()     { step "master the ISO";  "$SANDBOX" "$TREE/iso/mkiso" "${ISO_PROFILE:-minimal}"; }

ALL="fetch kernel rootfs usable pkgs iso"
STEPS=${*:-$ALL}

for s in $STEPS; do
	case "$s" in
	fetch)   do_fetch ;;
	kernel)  do_kernel ;;
	rootfs)  do_rootfs ;;
	usable)  do_usable ;;
	pkgs)    do_pkgs ;;
	iso)     do_iso ;;
	*) echo "build.sh: unknown step '$s' (want: $ALL)" >&2; exit 1 ;;
	esac
done

step "done"
