#!/usr/bin/env python3
"""Generate Arctic port recipes from the package manifest.

Hand-writing several hundred recipes means several hundred chances to get a
configure flag wrong. Instead the manifest carries what is actually specific to
a package - name, version, licence, dependencies, upstream URL - and the build
system template supplies the rest. This is the same split every large
distribution ends up making.

    ./gen-ports.py                  regenerate every recipe from manifest.tsv
    ./gen-ports.py --check          verify recipes match the manifest
    ./gen-ports.py --stats          count packages per repo

Manifest columns, tab separated:
    repo  name  version  buildsys  license  depends  makedepends  url  source  desc

`depends` and `makedepends` are comma separated. `source` may contain {name},
{version} and {V_} (version with underscores); if it is "-" the package is a
meta package with no payload.
"""
import os
import sys
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, "manifest.tsv")

# --------------------------------------------------------------------- templates

HEADER = """# {name} - {desc}
# Generated from manifest.tsv by gen-ports.py. Edit the manifest, not this file,
# unless the package needs something the template cannot express - in which case
# drop a `recipe.local` beside it and it will be preserved.
name={name}
version={version}
release=1
desc="{desc}"
url="{url}"
license="{license}"
depend="{depends}"
makedepend="{makedepends}"
source="{source}"
sha256="{sums}"
"""

TEMPLATES = {
    # ------------------------------------------------------------- autotools
    "autotools": """
build() {{
	cd "{srcdir}"
	./configure \\
		--prefix=/usr \\
		--sysconfdir=/etc \\
		--localstatedir=/var \\
		--libdir=/usr/lib \\
		--disable-static \\
		--disable-nls
	make -j"$JOBS"
}}

package() {{
	cd "{srcdir}"
	make DESTDIR="$pkgdir" install
}}
""",
    # -------------------------------------------------------- autotools, no nls
    "autotools-nodisable": """
build() {{
	cd "{srcdir}"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
	make -j"$JOBS"
}}

package() {{
	cd "{srcdir}"
	make DESTDIR="$pkgdir" install
}}
""",
    # ------------------------------------------------------------------ cmake
    "cmake": """
build() {{
	cmake -S "{srcdir}" -B build -G Ninja \\
		-DCMAKE_INSTALL_PREFIX=/usr \\
		-DCMAKE_INSTALL_LIBDIR=lib \\
		-DCMAKE_BUILD_TYPE=Release \\
		-DBUILD_SHARED_LIBS=ON
	ninja -C build -j"$JOBS"
}}

package() {{
	DESTDIR="$pkgdir" ninja -C build install
}}
""",
    # ------------------------------------------------------------------ meson
    "meson": """
build() {{
	cd "{srcdir}"
	meson setup build \\
		--prefix=/usr \\
		--libdir=/usr/lib \\
		--sysconfdir=/etc \\
		--localstatedir=/var \\
		--buildtype=release \\
		--wrap-mode=nodownload \\
		-Db_lto=true
	ninja -C build -j"$JOBS"
}}

package() {{
	cd "{srcdir}"
	DESTDIR="$pkgdir" ninja -C build install
}}
""",
    # ------------------------------------------------------------------ cargo
    "cargo": """
build() {{
	cd "{srcdir}"
	# Arctic builds Rust offline against a vendored tree so packages are
	# reproducible and the build host needs no network.
	export RUSTFLAGS="-C linker=clang -C link-arg=-fuse-ld=lld"
	cargo build --release --locked --offline
}}

package() {{
	cd "{srcdir}"
	install -Dm755 "target/release/{name}" "$pkgdir/usr/bin/{name}"
	for d in README.md README LICENSE; do
		[ -f "$d" ] && install -Dm644 "$d" "$pkgdir/usr/share/doc/{name}/$d"
	done
	true
}}
""",
    # ----------------------------------------------------------------- python
    "python": """
build() {{
	cd "{srcdir}"
	python -m build --wheel --no-isolation
}}

package() {{
	cd "{srcdir}"
	python -m installer --destdir="$pkgdir" dist/*.whl
}}
""",
    # --------------------------------------------------------------------- go
    "go": """
build() {{
	cd "{srcdir}"
	export CGO_CPPFLAGS="$CPPFLAGS" CGO_CFLAGS="$CFLAGS" CGO_LDFLAGS="$LDFLAGS"
	export GOFLAGS="-buildmode=pie -trimpath -mod=readonly -modcacherw"
	go build -o "{name}" .
}}

package() {{
	cd "{srcdir}"
	install -Dm755 "{name}" "$pkgdir/usr/bin/{name}"
}}
""",
    # ------------------------------------------------------------ plain make
    "make": """
build() {{
	cd "{srcdir}"
	make -j"$JOBS" PREFIX=/usr
}}

package() {{
	cd "{srcdir}"
	make PREFIX=/usr DESTDIR="$pkgdir" install
}}
""",
    # ------------------------------------------- suckless: configure by editing
    "suckless": """
build() {{
	cd "{srcdir}"
	# Suckless software is configured in the source. Arctic ships a config.h
	# with the Arctic palette; replace it and rebuild to change anything.
	[ -f config.def.h ] && cp -f config.def.h config.h
	make -j"$JOBS" PREFIX=/usr
}}

package() {{
	cd "{srcdir}"
	make PREFIX=/usr DESTDIR="$pkgdir" install
	[ -f config.h ] && install -Dm644 config.h "$pkgdir/usr/share/{name}/config.h"
	true
}}
""",
    # ---------------------------------------------------------- kernel module
    "dkms": """
# Built against every installed kernel. alpm re-runs this from the package's
# post_upgrade hook whenever a kernel changes, which is what dkms is for.
#
# gmake, not make: Linux's kbuild is written against GNU make and bmake cannot
# drive it. /usr/bin/make on Arctic is bmake, so kernel modules ask for gmake
# explicitly.
build() {{
	cd "{srcdir}"
	for kdir in /usr/lib/modules/*/build; do
		[ -d "$kdir" ] || continue
		gmake -C "$kdir" M="$PWD" modules
	done
}}

package() {{
	cd "{srcdir}"
	for kver in $(ls /usr/lib/modules); do
		install -d "$pkgdir/usr/lib/modules/$kver/extra"
		for ko in *.ko; do
			[ -f "$ko" ] && install -Dm644 "$ko" \\
				"$pkgdir/usr/lib/modules/$kver/extra/$ko"
		done
	done
	true
}}
""",
    # ------------------------------------------------------------------- qmake
    "qmake": """
build() {{
	cd "{srcdir}"
	qmake6 PREFIX=/usr
	make -j"$JOBS"
}}

package() {{
	cd "{srcdir}"
	make INSTALL_ROOT="$pkgdir" install
}}
""",
    # -------------------------------------------------------------------- meta
    "meta": """
# A meta package: the dependency list is the whole payload. Installing it pulls
# in a working setup and nothing else.
package() {{
	install -d "$pkgdir/usr/share/arctic/meta"
	printf '%s\\n' "{depends}" >"$pkgdir/usr/share/arctic/meta/{name}"
}}
""",
    # ------------------------------------------------------- prebuilt binaries
    "binary": """
# Repackaged upstream build. Arctic prefers to compile from source, but a few
# things ship only as binaries; those live here with the licence stated plainly.
options="!strip"

package() {{
	cd "{srcdir}"
	install -d "$pkgdir/opt/{name}"
	cp -a . "$pkgdir/opt/{name}/"
	install -d "$pkgdir/usr/bin"
	ln -sf "/opt/{name}/{name}" "$pkgdir/usr/bin/{name}"
}}
""",
    # --------------------------------------------------------------- firmware
    "firmware": """
options="!strip"

package() {{
	cd "{srcdir}"
	install -d "$pkgdir/usr/lib/firmware"
	cp -a . "$pkgdir/usr/lib/firmware/"
	find "$pkgdir/usr/lib/firmware" -name 'Makefile' -delete
	true
}}
""",
    # ----------------------------------------------------------- xorg driver
    "xorg": """
build() {{
	cd "{srcdir}"
	./configure --prefix=/usr
	make -j"$JOBS"
}}

package() {{
	cd "{srcdir}"
	make DESTDIR="$pkgdir" install
	find "$pkgdir" -name '*.la' -delete
	true
}}
""",
}


def srcdir_for(name, version, source):
    """Work out the directory a tarball unpacks into."""
    if source == "-":
        return "."
    first = source.split()[0]
    fn = first.split("::")[0] if "::" in first else os.path.basename(first)
    for ext in (".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".zip", ".tar"):
        if fn.endswith(ext):
            fn = fn[: -len(ext)]
            break
    # A github archive tarball named v1.2.3.tar.gz unpacks to name-1.2.3.
    if fn.startswith("v") and fn[1:2].isdigit():
        fn = f"{name}-{fn[1:]}"
    return fn or f"{name}-{version}"


def render(row):
    repo, name, version, buildsys, lic, deps, mdeps, url, source, desc = row

    src = (source
           .replace("{name}", name)
           .replace("{version}", version)
           .replace("{V_}", version.replace(".", "_")))
    if src == "-":
        src = ""

    nsrc = len(src.split()) if src else 0
    sums = "\n\t".join(["SKIP"] * nsrc) if nsrc else ""

    body = TEMPLATES.get(buildsys)
    if body is None:
        raise SystemExit(f"{name}: unknown build system '{buildsys}'")

    text = HEADER.format(
        name=name, version=version, desc=desc, url=url, license=lic,
        depends=" ".join(d.strip() for d in deps.split(",") if d.strip() and d != "-"),
        makedepends=" ".join(d.strip() for d in mdeps.split(",") if d.strip() and d != "-"),
        source=src, sums=sums,
    )
    text += body.format(
        name=name, version=version,
        srcdir=srcdir_for(name, version, src or "-"),
        depends=" ".join(d.strip() for d in deps.split(",") if d.strip() and d != "-"),
    )
    return text


def load():
    rows = []
    with open(MANIFEST) as f:
        for lineno, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 10:
                raise SystemExit(
                    f"manifest.tsv:{lineno}: expected 10 columns, found {len(parts)}\n  {line[:90]}")
            rows.append(parts)
    return rows


def main():
    rows = load()
    mode = sys.argv[1] if len(sys.argv) > 1 else "--write"

    per_repo = collections.Counter(r[0] for r in rows)
    names = collections.Counter(r[1] for r in rows)
    dupes = [n for n, c in names.items() if c > 1]
    if dupes:
        raise SystemExit(f"duplicate package names in the manifest: {', '.join(sorted(dupes))}")

    if mode == "--stats":
        total = 0
        for repo, n in sorted(per_repo.items()):
            print(f"  {repo:<14} {n:>4}")
            total += n
        print(f"  {'total':<14} {total:>4}")
        buildsys = collections.Counter(r[3] for r in rows)
        print("\n  by build system")
        for b, n in buildsys.most_common():
            print(f"  {b:<14} {n:>4}")
        return

    written = 0
    for row in rows:
        repo, name = row[0], row[1]
        d = os.path.join(HERE, repo, name)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "recipe")

        # A recipe.local means a human took over; never clobber it.
        if os.path.exists(os.path.join(d, "recipe.local")):
            continue
        text = render(row)

        if mode == "--check":
            if not os.path.exists(path) or open(path).read() != text:
                print(f"  stale: {repo}/{name}")
            continue

        # Hand-written recipes (the core packages) are kept as they are.
        if os.path.exists(path) and "Generated from manifest.tsv" not in open(path).read():
            continue

        with open(path, "w") as f:
            f.write(text)
        written += 1

    if mode != "--check":
        print(f"wrote {written} recipes across {len(per_repo)} repositories")
        print(f"total packages in the manifest: {len(rows)}")


if __name__ == "__main__":
    main()
