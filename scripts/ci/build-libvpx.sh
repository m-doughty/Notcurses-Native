#!/usr/bin/env bash
# Build + install libvpx — Google's VP8 / VP9 codec. Linked into our
# source-built ffmpeg via --enable-libvpx so VP8/9 video decode has
# the same accelerated path users get on package-managed lanes.
#
# Honours $PREFIX (default /usr/local). Honours $MACOSX_DEPLOYMENT_TARGET
# on macOS — libvpx's configure passes it through to clang.
#
# Configure is a hand-rolled script (not autotools), with its own
# arch/CPU detection. nasm or yasm is needed on x86_64 for SIMD
# acceleration; libvpx tolerates either.
#
# Windows/MSYS2 is the one platform where this script has to diverge,
# and both divergences are imposed by upstream rather than chosen:
#
#   1. The target must be named explicitly. libvpx auto-detects it
#      from `$CC -dumpmachine` and its OS table only knows the strings
#      `x86_64*mingw32*` and `*mingw32*` (build/make/configure.sh
#      ~:839). UCRT64's gcc reports `x86_64-w64-mingw32` and lands on
#      x86_64-win64-gcc by luck; CLANGARM64's clang reports
#      `aarch64-w64-windows-gnu`, which matches nothing there, so
#      libvpx silently falls through to `generic-gnu` — a NEON-less
#      build with the wrong ABI assumptions that would still compile.
#      Naming the target removes the guesswork on both lanes.
#      `arm64-win64-gcc` is a first-class entry in 1.16.0's
#      all_platforms list (configure:109), so the arm64 lane is
#      supported upstream, not a hack.
#
#   2. Static only. libvpx's configure hard-refuses shared libraries
#      anywhere but ELF/OS-2/Darwin — "--enable-shared only supported
#      on ELF, OS/2, and Darwin for now" (configure:575). The escape
#      hatch one line above it is `enabled gnu`, and `gnu` is only set
#      for the literal `generic-gnu` toolchain, never for
#      `*-win64-gcc`, so there is no flag combination that produces a
#      libvpx DLL from this build system. We therefore build libvpx.a
#      and let ffmpeg absorb it into avcodec-<N>.dll; build-ffmpeg.sh
#      already passes --pkg-config-flags=--static, so pkgconf hands
#      ffmpeg vpx.pc's Libs plus Libs.private and the link resolves.
#      Two consequences worth knowing downstream: there is no
#      libvpx-*.dll to bundle on Windows, and the libvpx_vp8 /
#      libvpx_vp9 decoders that run-codec-probe.sh gates on live
#      inside avcodec itself. libvpx is BSD-3-Clause, so folding it
#      into an LGPL-2.1 shared library raises no licensing question.
#      (MSYS2's own mingw-w64-*-libvpx package does ship a
#      libvpx-1.dll — it is built through libvpx's separate CMake
#      build system, not this configure. Static suits us better
#      anyway: same decoders, one fewer DLL in the archive.)
set -euxo pipefail

# 1.16.0 — current stable (1.17.0 is still at -rc, and we don't ship
# release candidates).
VERSION='1.16.0'
URL="https://github.com/webmproject/libvpx/archive/refs/tags/v${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o libvpx.tar.gz "$URL"
tar -xzf libvpx.tar.gz
cd "libvpx-${VERSION}"

# Decoders are all we care about (notcurses doesn't encode video);
# disabling encoders would skip a chunk of unused build, but
# `--enable-vp8 --enable-vp9` enables encoder + decoder both — we
# keep them all on because the encoder objects add < 1 MB and
# disabling them risks subtle linker grief inside ffmpeg's
# --enable-libvpx check.
configure_args=(
    --prefix="$PREFIX"
    --libdir="$PREFIX/lib"
    --enable-pic
    --enable-vp8
    --enable-vp9
    --disable-examples
    --disable-tools
    --disable-docs
    --disable-unit-tests
    --disable-install-bins
    --disable-install-srcs
)

# Linkage + target selection. See the header for why Windows is the
# odd one out on both counts.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        case "${MSYSTEM_CARCH:-}" in
            x86_64)  vpx_target='x86_64-win64-gcc' ;;
            aarch64) vpx_target='arm64-win64-gcc'  ;;
            '')
                echo "❌ MSYSTEM_CARCH is unset inside an MSYS2 shell." >&2
                echo "   Refusing to let libvpx guess its target: on CLANGARM64" >&2
                echo "   the guess is 'generic-gnu', which builds but is wrong." >&2
                exit 1
                ;;
            *)
                echo "❌ Unhandled MSYSTEM_CARCH='$MSYSTEM_CARCH'." >&2
                echo "   Map it to a libvpx target from ./configure --help's" >&2
                echo "   platform list before adding that MSYS2 environment." >&2
                exit 1
                ;;
        esac
        configure_args+=( --target="$vpx_target" --disable-shared --enable-static )
        ;;
    *)
        configure_args+=( --enable-shared --disable-static )
        ;;
esac

./configure "${configure_args[@]}"
make -j"$JOBS"
make install

# libvpx's macOS build leaves the dylib's install_name as a bare
# leaf name (e.g. "libvpx.9.dylib") — no @rpath/ prefix, no
# absolute path. This is fine for direct linking + DT_NEEDED
# resolution via fallback paths, but breaks downstream
# dylibbundler when notcurses → dylibbundler tries to walk the
# dep tree. dylibbundler can't resolve a bare leaf name back to
# a file and dies with "Cannot resolve path libvpx.X.dylib"
# followed by an otool "can't open file" error. Patch the
# install_name to @rpath/<leaf> so dylibbundler can do its job.
# Linux dylibs don't have this concept (DT_SONAME is always a
# leaf-style name without prefix, and patchelf later handles
# rpath separately), so this fixup is macOS-only.
if [[ "$(uname -s)" == "Darwin" ]]; then
    for dylib in "$PREFIX/lib"/libvpx.*.dylib; do
        [[ -L "$dylib" ]] && continue
        leaf=$(basename "$dylib")
        install_name_tool -id "@rpath/$leaf" "$dylib"
        echo "  patched install_name: $dylib  ->  @rpath/$leaf"
    done
fi

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion vpx

cd /
rm -rf "/tmp/libvpx-${VERSION}" /tmp/libvpx.tar.gz
