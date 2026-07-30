#!/bin/sh
cd /home/apiwo/arctic-build/src || exit 1
while read -r name url; do
  [ -n "$name" ] || continue
  [ -s "$name" ] && { echo "have $name"; continue; }
  echo "fetch $name"
  curl -fL --retry 3 --retry-delay 2 -o "$name.part" "$url" && mv "$name.part" "$name" || echo "FAIL $name"
done < ../sources.list
echo "=== FETCH DONE ==="
ls -la
