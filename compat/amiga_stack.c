/* A Shell gives 4 KB of stack; libnix's startup sets this much up instead.
 * Copyright (c) 2026 AmiCradle Team. GPL 3 or later, like The Sound of Sorting. */
unsigned long __stack = 512 * 1024;
static const char version[] __attribute__((used)) = "$VER: SoundOfSorting 0.6.5 Amiga (16.11.2026)";
