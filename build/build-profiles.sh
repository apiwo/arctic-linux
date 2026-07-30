#!/bin/sh
# Build the profile packages into repo/profile.
set -u
[ "${ARCTIC_SANDBOX:-0}" = "1" ] || { echo "run through arctic-sandbox" >&2; exit 1; }
B=/home/apiwo/arctic-build
TREE=/home/apiwo/arctic
export ALPM_CACHE="$B/profile-cache"
export ALPM_BUILDROOT="$B/profile-build"
export ALPM_COLOR=never
mkdir -p "$B/repo/profile/x86_64"

ok=0; bad=0
for d in "$TREE"/ports/profile/*/; do
	[ -f "$d/recipe" ] || continue
	n=$(basename "$d")
	if sh "$TREE/alpm/alpm-build" "$d/recipe" >"$B/logs/profile-$n.log" 2>&1; then
		f=$(ls -t "$ALPM_BUILDROOT/out/$n"-*.alpmz 2>/dev/null | head -1)
		if [ -n "$f" ]; then
			cp -f "$f" "$B/repo/profile/x86_64/"
			printf '   ok   %s\n' "$(basename "$f")"; ok=$((ok+1))
		else
			printf '   FAIL %s (no package produced)\n' "$n"; bad=$((bad+1))
		fi
	else
		printf '   FAIL %s (see logs/profile-%s.log)\n' "$n" "$n"; bad=$((bad+1))
	fi
done
sh "$TREE/alpm/alpm-repo" gen "$B/repo/profile" x86_64 >/dev/null 2>&1
printf '\n   %s built, %s failed\n' "$ok" "$bad"
