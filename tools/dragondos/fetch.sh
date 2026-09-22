#!/bin/sh
# Build the DragonDOS CLI (robcfg/retrotools, pinned) into bin/dragondos.
#
# The upstream repo is a larger multi-tool project; this fetches one pinned
# commit, applies the two patches in ./patches (CLI-only build, and raw
# .dsk geometry inference), builds the CLI, and installs it. bin/ is
# gitignored and reproducible, same as the emulator itself.
set -e

PIN=2d5723a3e740b7344f1eb9533f07c36335570b2b   # 2025-09-30
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/xroar-dev/retrotools-$PIN"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${XROAR_DEV_BIN:-$(cd "$HERE/../.." && pwd)/bin}"

if [ ! -d "$CACHE" ]; then
    git clone --quiet --depth 1 "https://github.com/robcfg/retrotools.git" "$CACHE"
    git -C "$CACHE" fetch --quiet --depth 1 origin "$PIN"
    git -C "$CACHE" checkout --quiet -q "$PIN"
fi

cd "$CACHE"
# apply the patch series if it is not already applied (idempotent)
if ! git apply --reverse --check "$HERE"/patches/*.patch >/dev/null 2>&1; then
    git apply "$HERE"/patches/*.patch
fi

cd dragondos
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release .. >/dev/null
make dragondos --quiet

mkdir -p "$OUT"
cp dragondos "$OUT/dragondos"
echo "built: $OUT/dragondos"

"$OUT/dragondos" help | head -4