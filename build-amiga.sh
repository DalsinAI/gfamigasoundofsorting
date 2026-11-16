#!/bin/sh
# Builds The Sound of Sorting for GFOS (AmigaOS 3.2.3 with GFOpenUp, on the
# GFOpenKick ROM or a Kickstart) with a stove: 68040, soft float with the FPU
# taken when there is one (fpuauto), on the GFOpenWX Toolkit, with the
# stove's SDL 2 (GFOpenGPU's link stubs) for the sound.
#   STOVE=.../stoves/os32-gcc16-open6 OUT=out ./build-amiga.sh
#   (WXT_SRC=... to use a toolkit tree already on disk)
# The Sound of Sorting, the toolkit and fpuauto are fetched at the commits
# soundofsorting.lock gives; nothing third-party is kept here. The build tree is
# kept, so a run that stops at BUDGET_TOTAL seconds goes on next time.
# OUT gets Parts/SoundOfSorting: a GFOpenUp part (its Part file and the files
# it puts in SYS:Utilities/SoundOfSorting; it needs the GFOpenGPU part, whose
# SDL2.module plays the sound), installed with
#   GFOpenUpTool INSTALL Parts/SoundOfSorting
# and tests/sorting-test, upstream's own check of every algorithm, for a lab
# Copyright (c) 2026 AmiCradle Team. GPL 3 or later, like The Sound of Sorting.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/soundofsorting.lock"
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
# outside the checkout: Cradle cleans it (git clean -ffdx) before every job
WORK="${WORK:-$HOME/.cache/gfamigasoundofsorting/build}"; OUT="${OUT:-$WORK/out}"; JOBS=${JOBS:-12}
TC="$STOVE/prefix"; PATH="$TC/bin:$PATH"; export PATH
mkdir -p "$WORK/deps" "$OUT"; OUT=$(cd "$OUT" && pwd)
t0=$(date +%s)

# a repository at one commit, fetched once (SPARSE: only those folders)
fetch() {
    d="$WORK/deps/$1"
    if [ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" != "$3" ]; then
        rm -rf "${d:?}"; mkdir -p "$d"
        git -C "$d" init -q
        if [ -n "${4:-}" ]; then
            git -C "$d" config core.sparseCheckout true
            echo "$4" > "$d/.git/info/sparse-checkout"
            git -C "$d" fetch -q --depth 1 --filter=blob:none "$2" "$3"
        else
            git -C "$d" fetch -q --depth 1 "$2" "$3"
        fi
        git -C "$d" checkout -q FETCH_HEAD
        [ "$(git -C "$d" rev-parse HEAD)" = "$3" ] || { echo "$1: commit mismatch"; exit 1; }
    fi
}

# --- the toolkit's SDK, again only when its tree changed ---------------------
if [ -z "${WXT_SRC:-}" ]; then fetch gfopenwxtoolkit "$WXT_REPO" "$WXT_COMMIT"; WXT_SRC="$WORK/deps/gfopenwxtoolkit"; fi
WXB="$WORK/gfopenwx"
WXREV=$( (git -C "$WXT_SRC" rev-parse HEAD 2>/dev/null; git -C "$WXT_SRC" diff HEAD 2>/dev/null) | sha256sum | cut -c1-16)
if [ ! -x "$WXB/out/sdk/bin/wx-config" ] || [ "$(cat "$WXB/out/.rev" 2>/dev/null)" != "$WXREV" ]; then
    # stopped here, before Cradle's own cap, so the log says how far it got
    set +e
    STOVE="$STOVE" WORK="$WXB" OUT="$WXB/out" JOBS=$JOBS timeout "${BUDGET_TOTAL:-840}" sh "$WXT_SRC/build-amiga.sh" > "$WORK.wx.log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 124 ]; then
        echo "toolkit: out of time after $(( $(date +%s) - t0 )) s, run again to go on"
        echo "  base objects: $(find "$WXB/base" -name '*.o' 2>/dev/null | wc -l), GUI objects: $(find "$WXB/gui/obj" -name '*.o' 2>/dev/null | wc -l)"
        tail -5 "$WORK.wx.log"
        exit 0
    fi
    [ "$rc" = 0 ] || { tail -40 "$WORK.wx.log"; exit 1; }
    [ -x "$WXB/out/sdk/bin/wx-config" ] || { tail -40 "$WORK.wx.log"; echo "no toolkit SDK"; exit 1; }
    echo "$WXREV" > "$WXB/out/.rev"
fi
echo "toolkit: $(( $(date +%s) - t0 )) s"
WXC="$WXB/out/sdk/bin/wx-config"

# --- fpuauto: libfpuauto.a and its link specs ---------------------------------
fetch fpuauto "$FPA_REPO" "$FPA_COMMIT" "/common/fpuauto/"
FA="$WORK/deps/fpuauto/common/fpuauto"; FAL="$WORK/fpuauto"
if [ ! -f "$FAL/libfpuauto.a" ] || [ "$(cat "$FAL/.rev" 2>/dev/null)" != "$FPA_COMMIT" ]; then
    rm -rf "$FAL"; mkdir -p "$FAL/obj"
    m68k-amigaos-gcc -m68040 -DFPUAUTO_COMMON -c "$FA/fpuauto.S" -o "$FAL/obj/fa_common.o"
    for n in $(sed 's/^--wrap=//' "$FA/fpuauto.wraps"); do
        m68k-amigaos-gcc -m68040 -DR_$n -c "$FA/fpuauto.S" -o "$FAL/obj/fa_$n.o"
    done
    m68k-amigaos-ar rcs "$FAL/libfpuauto.a" "$FAL"/obj/fa_*.o
    echo "$FPA_COMMIT" > "$FAL/.rev"
fi

# --- The Sound of Sorting at its pinned commit, with patches/ -----------------
SRC="$WORK/sound-of-sorting"
PSUM=$(cat "$HERE"/patches/*.patch | sha256sum | cut -c1-16)
if [ "$(cat "$SRC/.patched" 2>/dev/null)" != "$SOS_COMMIT-$PSUM" ]; then
    rm -rf "$SRC"; mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" fetch -q --depth 1 "$SOS_GIT" "$SOS_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
    [ "$(git -C "$SRC" rev-parse HEAD)" = "$SOS_COMMIT" ] || { echo "commit mismatch"; exit 1; }
    for p in "$HERE"/patches/*.patch; do
        patch -s -d "$SRC" -p1 < "$p" || { echo "patch failed: $p"; exit 1; }
    done
    echo "$SOS_COMMIT-$PSUM" > "$SRC/.patched"
    rm -rf "$WORK/obj"
fi

# objects made against another toolkit commit go: its headers are not in
# the make rules, and stale objects crash at start (gfamigagolly #3)
if [ "$(cat "$WORK/.toolkit-objs" 2>/dev/null)" != "$WXT_COMMIT" ]; then
    rm -rf "$WORK/obj"
    echo "$WXT_COMMIT" > "$WORK/.toolkit-objs"
fi

# --- SDL 2 from the stove's SDK ------------------------------------------------
SDK="$TC/m68k-amigaos"
for f in include/SDL2/SDL.h lib/libSDL2.a; do
    [ -f "$SDK/$f" ] || { echo "the stove has no $f"; exit 2; }
done

# --- one Makefile: the program and upstream's test -----------------------------
LATE=""
if m68k-amigaos-gcc -fno-late-combine-instructions -S -o /dev/null -x c /dev/null 2>/dev/null; then LATE="-fno-late-combine-instructions"; fi
CF="-noixemul -m68040 -O2 -fno-delete-null-pointer-checks $LATE -DNDEBUG"
O="$WORK/obj"; mkdir -p "$O"
COMMON="SortArray SortSound SortAlgo algorithms/timsort algorithms/wikisort"
APP="WMain wxg/WMain_wxg wxg/WAbout_wxg WSortView wxClickText"
M="$O/Makefile"
{
    echo "CXXF = $CF -std=gnu++11 $("$WXC" --cxxflags) -I$SDK/include/SDL2 -I$SRC/src -Wno-deprecated-declarations"
    C=""; for f in $COMMON; do o="c_$(echo "$f" | tr / _).o"; C="$C $o"; printf '%s: %s\n\tm68k-amigaos-g++ $(CXXF) -MMD -c $< -o $@\n' "$o" "$SRC/src/$f.cpp"; done
    A=""; for f in $APP; do o="a_$(echo "$f" | tr / _).o"; A="$A $o"; printf '%s: %s\n\tm68k-amigaos-g++ $(CXXF) -MMD -c $< -o $@\n' "$o" "$SRC/src/$f.cpp"; done
    printf 'SortTest.o: %s\n\tm68k-amigaos-g++ $(CXXF) -MMD -c $< -o $@\n' "$SRC/src/SortTest.cpp"
    printf 'amiga_stack.o: %s\n\tm68k-amigaos-gcc %s -c $< -o $@\n' "$HERE/compat/amiga_stack.c" "$CF"
    echo "COMMONOBJS =$C"
    echo "APPOBJS =$A amiga_stack.o"
    echo "all: \$(COMMONOBJS) \$(APPOBJS) SortTest.o"
    echo "-include *.d"
} > "$M"
left=$(( ${BUDGET_TOTAL:-840} - ($(date +%s) - t0) ))
[ "$left" -gt 60 ] || { echo "no time left for The Sound of Sorting this run"; exit 0; }
set +e
(cd "$O" && timeout "$left" nice -n 19 make -k -j"$JOBS" all > make.log 2>&1)
rc=$?
set -e
grep -E 'error|Error' "$O/make.log" | head -60
[ "$rc" = 0 ] || { [ "$rc" = 124 ] && echo "out of time: run again to go on"; tail -20 "$O/make.log"; echo "compile: $(( $(date +%s) - t0 )) s"; exit "$rc"; }
echo "compile: $(( $(date +%s) - t0 )) s"

# --- the links: soft-float specs, then fpuauto's ------------------------------
objs() { (cd "$O" && for f in $(sed -n "s/^$1 =//p" Makefile); do echo "$O/$f"; done); }
LINK="m68k-amigaos-g++ -noixemul -m68040 -specs=$HERE/scripts/m68k-soft-m68040.specs -specs=$FA/fpuauto.specs -L$FAL"
# shellcheck disable=SC2046,SC2086
$LINK -o "$O/SoundOfSorting.debug" $(objs APPOBJS) $(objs COMMONOBJS) \
    $("$WXC" --libs std) -L"$SDK/lib" -lSDL2 -lGL > "$O/link.log" 2>&1 || { head -60 "$O/link.log"; exit 1; }
# shellcheck disable=SC2046,SC2086
$LINK -o "$O/sorting-test.debug" "$O/SortTest.o" "$O/amiga_stack.o" $(objs COMMONOBJS) \
    $("$WXC" --libs base) -L"$SDK/lib" -lSDL2 -lGL > "$O/link-test.log" 2>&1 || { head -60 "$O/link-test.log"; exit 1; }

# --- the GFOpenUp part: Parts/SoundOfSorting ----------------------------------
P="$OUT/Parts/SoundOfSorting"; rm -rf "$P"; mkdir -p "$P/Utilities/SoundOfSorting"
m68k-amigaos-strip -o "$P/Utilities/SoundOfSorting/SoundOfSorting" "$O/SoundOfSorting.debug"
cp "$SRC/COPYING" "$SRC/README.md" "$P/Utilities/SoundOfSorting/"
sh "$HERE/scripts/write-part.sh" "$P" "$SOS_VERSION"
mkdir -p "$OUT/tests"; m68k-amigaos-strip -o "$OUT/tests/sorting-test" "$O/sorting-test.debug"
ls -l "$P/Utilities/SoundOfSorting/SoundOfSorting" "$OUT/tests/sorting-test"
echo "part: $(grep -c '^copy' "$P/Part") files, $(du -sk "$P" | cut -f1) KB"
echo "fpuauto: $(m68k-amigaos-nm "$O/SoundOfSorting.debug" | grep -c ' T ___wrap_') wrapped routines"
echo "total: $(( $(date +%s) - t0 )) s"
