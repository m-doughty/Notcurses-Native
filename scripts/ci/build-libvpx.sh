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
set -euxo pipefail

VERSION='1.14.1'
URL="https://github.com/webmproject/libvpx/archive/refs/tags/v${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 --retry-all-errors -o libvpx.tar.gz "$URL"
tar -xzf libvpx.tar.gz
cd "libvpx-${VERSION}"

# Decoders are all we care about (notcurses doesn't encode video);
# disabling encoders would skip a chunk of unused build, but
# `--enable-vp8 --enable-vp9` enables encoder + decoder both — we
# keep them all on because the encoder objects add < 1 MB and
# disabling them risks subtle linker grief inside ffmpeg's
# --enable-libvpx check.
./configure \
    --prefix="$PREFIX" \
    --libdir="$PREFIX/lib" \
    --enable-shared \
    --disable-static \
    --enable-pic \
    --enable-vp8 \
    --enable-vp9 \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests \
    --disable-install-bins \
    --disable-install-srcs
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
