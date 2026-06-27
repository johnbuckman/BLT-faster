#!/bin/sh
# Apply the BLT-faster patch to a BLT 2.4 source tree.
#
# Usage:  ./apply-patch.sh /path/to/blt
#
# Where /path/to/blt is the BLT package root (the directory that contains src/).
# In AndroWish/undroidwish that is jni/blt.
set -e

here=$(cd "$(dirname "$0")" && pwd)
patch_file="$here/patches/blt-faster.patch"

blt="$1"
if [ -z "$blt" ]; then
    echo "usage: $0 /path/to/blt   (the directory containing src/bltGraph.c)" >&2
    exit 2
fi
if [ ! -f "$blt/src/bltGraph.c" ]; then
    echo "error: $blt/src/bltGraph.c not found -- not a BLT source root?" >&2
    exit 2
fi

echo "Applying $patch_file to $blt ..."
# dry-run first so we fail cleanly if it doesn't apply
if ! patch -p1 -d "$blt" --dry-run < "$patch_file" >/dev/null 2>&1; then
    echo "error: patch does not apply cleanly to $blt." >&2
    echo "       (already patched? wrong BLT version? try: patch -p1 -d \"$blt\" < \"$patch_file\")" >&2
    exit 1
fi
patch -p1 -d "$blt" < "$patch_file"

echo
echo "Done. Now rebuild BLT the way you normally do."
echo "Both -cachelabels and -bufferchrome are now ON by default;"
echo "disable per-graph with '-cachelabels 0' / '-bufferchrome 0'."
