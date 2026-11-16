#!/bin/sh
# Host test for scripts/write-part.sh: the Part file GFOpenUpTool reads.
# Copyright (c) 2026 AmiCradle Team. GPL 3 or later, like The Sound of Sorting.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/Utilities/SoundOfSorting/images" "$T/Utilities/SoundOfSorting/docs"
: > "$T/Utilities/SoundOfSorting/SoundOfSorting"; : > "$T/Utilities/SoundOfSorting/images/icon32.png"; : > "$T/Utilities/SoundOfSorting/docs/tutorial.cts"
sh "$HERE/../scripts/write-part.sh" "$T" 0.6.5
fail=0
expect() { grep -qxF "$1" "$T/Part" || { echo "FAIL: no line: $1"; fail=1; }; }
expect 'part SoundOfSorting 0.6.5'
expect 'needs 68040'
expect 'needs part GFOpenGPU'
expect 'copy "Utilities/SoundOfSorting/SoundOfSorting" "SYS:Utilities/SoundOfSorting/SoundOfSorting"'
expect 'copy "Utilities/SoundOfSorting/images/icon32.png" "SYS:Utilities/SoundOfSorting/images/icon32.png"'
expect 'copy "Utilities/SoundOfSorting/docs/tutorial.cts" "SYS:Utilities/SoundOfSorting/docs/tutorial.cts"'
[ "$(head -1 "$T/Part")" = 'part SoundOfSorting 0.6.5' ] || { echo "FAIL: first line"; fail=1; }
[ "$(grep -c '^copy' "$T/Part")" = 3 ] || { echo "FAIL: copy count (the Part file itself must not be listed)"; fail=1; }
sh "$HERE/../scripts/write-part.sh" "$T" 0.6.5   # a second run: same file
[ "$(grep -c '^copy' "$T/Part")" = 3 ] || { echo "FAIL: second run lists the Part file"; fail=1; }
[ $fail = 0 ] && echo "Part file: all checks passed"
exit $fail
