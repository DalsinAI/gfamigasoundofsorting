#!/bin/sh
# Writes the Part file GFOpenUpTool INSTALL reads (gfopenup src/openuptool.c):
# one "copy" line per file under the part drawer, each to SYS:<its path>.
#   write-part.sh <part drawer> <version>
# Copyright (c) 2026 AmiCradle Team. GPL 3 or later, like The Sound of Sorting.
set -eu
P=$1; V=$2
{
    echo "part SoundOfSorting $V"
    echo "; The Sound of Sorting: sorting algorithms shown and heard, step by step"
    echo "needs 68040"
    echo "needs part GFOpenGPU"
    (cd "$P" && find Utilities -type f ! -name Part | LC_ALL=C sort) | while read -r f; do
        echo "copy \"$f\" \"SYS:$f\""
    done
} > "$P/Part"
