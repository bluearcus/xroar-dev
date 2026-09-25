#!/bin/sh
# Build the vendored vdk2dsk into bin/.  Single-file C, no dependencies.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$HERE/../.."          # repo root
BIN="$OUT/bin"

mkdir -p "$BIN"
cc -O2 -Wall -Wextra -Werror -o "$BIN/vdk2dsk" "$HERE/vdk2dsk.c"

echo "built: $BIN/vdk2dsk"
"$BIN/vdk2dsk" 2>&1 | head -1 || true