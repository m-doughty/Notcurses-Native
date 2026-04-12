[![Actions Status](https://github.com/m-doughty/Notcurses-Native/actions/workflows/test.yml/badge.svg)](https://github.com/m-doughty/Notcurses-Native/actions)

NAME
====

Notcurses::Native - Complete NativeCall bindings for the notcurses TUI library

SYNOPSIS
========

```raku
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

# Initialize notcurses
my $nc = notcurses_init(NotcursesOptions.new, Pointer);
my $std = notcurses_stdplane($nc);

# Write colored text
ncplane_set_fg_rgb8($std, 0, 255, 128);
ncplane_putstr_yx($std, 0, 0, 'Hello from notcurses!');
notcurses_render($nc);

# Wait for input
my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);

notcurses_stop($nc);
```

DESCRIPTION
===========

Notcurses::Native provides complete 1:1 NativeCall bindings for [notcurses](https://github.com/dankamongmen/notcurses) v3.0.16, a modern terminal UI library supporting rich text, colors, images, video, and pixel-perfect rendering via Sixel and Kitty graphics protocols.

This module vendors notcurses and builds it from source, so no system installation of notcurses is required. FFmpeg is used for multimedia support (image/video loading).

**606 functions** are bound across 9 modules, covering 100% of the bindable notcurses API. The only unbound functions are 4 `vprintf` variants that take `va_list`, which cannot be bridged through any FFI.

MODULES
=======

Notcurses::Native
-----------------

Core context management: init, stop, render, input, capabilities.

```raku
use Notcurses::Native;

my $nc = notcurses_init(NotcursesOptions.new, Pointer);
notcurses_render($nc);
my $ni = Ncinput.new;
my $key = notcurses_get_blocking($nc, $ni);
notcurses_stop($nc);
```

Key functions: `notcurses_init`, `notcurses_stop`, `notcurses_render`, `notcurses_stdplane`, `notcurses_get_blocking`, `notcurses_get_nblock`, `notcurses_cantruecolor`, `notcurses_canutf8`, `notcurses_mice_enable`.

Notcurses::Native::Types
------------------------

All CStruct definitions, enums, constants, and opaque handle types.

**CStruct types:** NotcursesOptions, NcplaneOptions, Nccell, Ncinput, Ncstats, Nccapabilities, Ncvgeom, NcvisualOptions, Timespec, and all widget options structs (NcselectorOptions, NcmenuOptions, NctabbedOptions, NcplotOptions, NcprogbarOptions, NcreaderOptions, etc.)

**Enums:** NcLogLevel, NcAlign, NcBlitter, NcScale, NcInputType, NcPixelImpl.

**Key constants:** 130 NCKEY_* key codes (NCKEY_UP, NCKEY_ESC, NCKEY_F01, NCKEY_BUTTON1, etc.), NCSTYLE_*, NCOPTION_*, NCALPHA_*, NCVISUAL_OPTION_*, NCMICE_*, NCBOX_*, NCKEY_MOD_*.

Notcurses::Native::Plane
------------------------

133 plane functions: create, destroy, write text, read back, cursor, colors, styles, channels, box drawing, lines, gradients, merge, resize, reparent, z-ordering, printf (variadic).

```raku
use Notcurses::Native::Plane;

my $child = ncplane_create($std, NcplaneOptions.new(:rows(10), :cols(40)));
ncplane_set_fg_rgb8($child, 255, 0, 0);
ncplane_putstr_yx($child, 0, 0, 'Red text');
ncplane_rounded_box($child, 0, 0, 9, 39, 0);
ncplane_destroy($child);
```

Notcurses::Native::Cell
-----------------------

56 cell functions: load characters, get/set colors, styles, channels, alpha, palette index, duplicate, compare, box cell helpers.

```raku
use Notcurses::Native::Cell;

my $c = Nccell.new;
nccell_load($plane, $c, 'A');
nccell_set_fg_rgb($c, 0xFF0000);
nccell_set_styles($c, NCSTYLE_BOLD);
my $text = nccell_strdup($plane, $c);
nccell_release($plane, $c);
```

Notcurses::Native::Channel
--------------------------

60 channel functions: pure computation on 32-bit single channels and 64-bit dual channels. Set/get RGB, alpha, palette index, default flags. Also pixel (ABGR uint32) creation and component access.

```raku
use Notcurses::Native::Channel;

my uint64 $channels = 0;
ncchannels_set_fg_rgb($channels, 0xFF0000);
ncchannels_set_bg_rgb($channels, 0x0000FF);
my $reversed = ncchannels_reverse($channels);
```

Notcurses::Native::Context
--------------------------

55 functions: pile operations, palette management, capabilities queries, statistics, alignment, string width, fade context, metric formatting, system info.

Notcurses::Native::Direct
-------------------------

70 direct mode functions: simple terminal control without full-screen takeover. Colors, styles, cursor, box drawing, input, capabilities.

```raku
use Notcurses::Native::Direct;

my $ncd = ncdirect_core_init(Str, Pointer, 0);
ncdirect_set_fg_rgb8($ncd, 255, 0, 0);
ncdirect_putstr($ncd, 0, "Red text\n");
ncdirect_stop($ncd);
```

Notcurses::Native::Input
------------------------

15 input query functions: modifier key predicates, key classification.

```raku
use Notcurses::Native::Input;

if ncinput_ctrl_p($ni) { say "Ctrl held" }
if nckey_synthesized_p($ni.id) { say "Synthesized key" }
if nckey_mouse_p($ni.id) { say "Mouse event" }
```

Notcurses::Native::Visual
-------------------------

23 visual/image functions: load from file, decode, resize, pixel manipulation, blit to planes, geometry queries.

```raku
use Notcurses::Native::Visual;

my $v = ncvisual_from_file('photo.png');
my $vopts = NcvisualOptions.new(:scaling(NCSCALE_SCALE), :blitter(NCBLIT_PIXEL));
$vopts.set-plane($std);
ncvisual_blit($nc, $v, $vopts);
ncvisual_destroy($v);
```

Notcurses::Native::Widgets
--------------------------

124 widget functions: progress bar, reel, selector, multiselector, tree, menu, tabbed, plot (uint64 and double), reader, FD plane, subprocess.

```raku
use Notcurses::Native::Widgets;

my $bar = ncprogbar_create($plane, NcprogbarOptions.new);
ncprogbar_set_progress($bar, 0.75e0);
ncprogbar_destroy($bar);
```

IMAGE VIEWING
=============

Notcurses supports multiple rendering backends for images. On terminals that support it (Kitty, iTerm2), pixel-perfect rendering is available:

```raku
my $v = ncvisual_from_file('image.png');

# Check for pixel protocol support
my $pixel-ok = notcurses_check_pixel_support($nc);

my $blitter = $pixel-ok > 0 ?? NCBLIT_PIXEL
    !! ncvisual_media_defblitter($nc, NCSCALE_SCALE);

my $plane = ncplane_create($std, NcplaneOptions.new(:rows($rows), :cols($cols)));
my $vopts = NcvisualOptions.new(:scaling(NCSCALE_SCALE), :blitter($blitter));
$vopts.set-plane($plane);
ncvisual_blit($nc, $v, $vopts);
```

INPUT HANDLING
==============

```raku
loop {
    my $ni = Ncinput.new;
    notcurses_get_blocking($nc, $ni);

    given $ni.id {
        when NCKEY_UP    { say "Up arrow" }
        when NCKEY_DOWN  { say "Down arrow" }
        when NCKEY_ESC   { last }
        when NCKEY_ENTER { say "Enter" }
        when NCKEY_F01   { say "F1" }
        default          { say "Key: {chr($ni.id)}" if $ni.id >= 32 }
    }

    if ncinput_ctrl_p($ni) { say "  +Ctrl" }
    if ncinput_shift_p($ni) { say "  +Shift" }
}
```

MOUSE SUPPORT
=============

```raku
notcurses_mice_enable($nc, NCMICE_ALL_EVENTS);

my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);
if nckey_mouse_p($ni.id) {
    say "Mouse at ({$ni.y}, {$ni.x})";
    say "Button 1" if $ni.id == NCKEY_BUTTON1;
    say "Scroll up" if $ni.id == NCKEY_SCROLL_UP;
}

notcurses_mice_disable($nc);
```

BUILD REQUIREMENTS
==================

Notcurses is vendored and built from source. You need:

  * CMake 3.14+

  * A C compiler (gcc, clang, or mingw-w64 under MSYS2)

  * `ncurses`, `libunistring`, `libdeflate` development headers

  * A multimedia backend for image/video support: **FFmpeg** on Linux/macOS, **OpenImageIO** on Windows

Linux (Debian / Ubuntu)
-----------------------

    sudo apt install \
        cmake pkg-config \
        libncurses-dev libunistring-dev libdeflate-dev \
        libavformat-dev libavcodec-dev libavdevice-dev \
        libavutil-dev libswscale-dev

Fedora / RHEL equivalents:

    sudo dnf install cmake pkgconf-pkg-config \
        ncurses-devel libunistring-devel libdeflate-devel ffmpeg-devel

macOS (Homebrew)
----------------

    brew install cmake pkg-config ffmpeg ncurses libunistring libdeflate

Windows (MSYS2 UCRT64)
----------------------

Windows support requires MSYS2 in its **UCRT64** environment — this produces native Windows DLLs via mingw-w64 GCC. Visual Studio / MSVC are not supported. Per upstream notcurses docs, OpenImageIO (not FFmpeg) is the recommended multimedia backend on Windows.

Install MSYS2 from [https://www.msys2.org/](https://www.msys2.org/), open a **UCRT64** shell, and:

    pacman -S \
        mingw-w64-ucrt-x86_64-cmake \
        mingw-w64-ucrt-x86_64-ninja \
        mingw-w64-ucrt-x86_64-toolchain \
        mingw-w64-ucrt-x86_64-libdeflate \
        mingw-w64-ucrt-x86_64-libunistring \
        mingw-w64-ucrt-x86_64-ncurses \
        mingw-w64-ucrt-x86_64-openimageio

Build tests (`notcurses-tester`) do not run on Windows — upstream limitation. The module builds and loads; terminal-dependent tests (`xt/`) need to be run on Linux or macOS.

Core-only (no multimedia)
-------------------------

If you don't need image/video support, you can omit the FFmpeg or OpenImageIO dependency. The build detects missing multimedia libraries and falls back automatically.

INSTALLATION
============

    zef install Notcurses::Native

Installation runs `t/` tests only — pure-Raku channel math and input struct tests that don't need a terminal. The full terminal-dependent test suite lives in `xt/` and can be run manually:

    prove -e 'raku -I lib -I t/lib' xt/*.rakutest

`prove` (Perl 5) is recommended for `xt/` tests because [prove6 has a bug](https://github.com/Raku/tap-harness6/issues/64) where terminal escape sequences from C libraries corrupt its TAP parser.

EXAMPLES
========

See the `examples/` directory for complete working programs:

  * `01-hello.raku` — Hello world

  * `02-colors.raku` — Color palette and style showcase

  * `03-boxes.raku` — Box drawing with nesting and colors

  * `04-input.raku` — Interactive keypress event viewer

  * `05-clock.raku` — Color-cycling real-time clock

  * `06-imgview.raku` — Terminal image viewer with pixel protocol support

  * `07-direct.raku` — Direct mode (no full-screen takeover)

  * `08-progress.raku` — Animated progress bar widgets

AUTHOR
======

Matt Doughty

COPYRIGHT AND LICENSE
=====================

Copyright 2026 Matt Doughty

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

