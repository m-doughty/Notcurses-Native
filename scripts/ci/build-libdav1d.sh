#!/usr/bin/env bash
# Build + install libdav1d — the VideoLAN AV1 decoder, ~10× faster
# than ffmpeg's internal AV1 decoder on 4K content. Linked into our
# source-built ffmpeg via --enable-libdav1d so AV1 video playback in
# notcurses matches the perf profile users get on package-managed
# lanes (musl/macOS arm64/Windows already bundle dav1d via their
# system ffmpeg).
#
# Honours $PREFIX (default /usr/local). Honours $MACOSX_DEPLOYMENT_TARGET
# on macOS — meson reads it via clang's defaults so produced dylibs
# stamp LC_BUILD_VERSION minos appropriately.
#
# Build system: meson + ninja. Caller must have both on PATH before
# invoking this script:
#   * manylinux_2_28: pip install meson ninja via /opt/python/cp*/bin
#   * macOS x86_64: brew install meson ninja (via x86_64 brew)
#
# nasm is needed on x86_64 for SIMD acceleration; not used on
# aarch64 (dav1d uses ARM-native NEON assembly there).
set -euxo pipefail

VERSION='1.4.3'
URL="https://code.videolan.org/videolan/dav1d/-/archive/${VERSION}/dav1d-${VERSION}.tar.bz2"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL -o dav1d.tar.bz2 "$URL"
tar -xjf dav1d.tar.bz2
cd "dav1d-${VERSION}"

# --default-library=shared — bundleable .so / .dylib.
# --buildtype=release — optimization on, strip-friendly.
# --strip — strip debug symbols at install time (smaller bundle).
# enable_tools=false / enable_tests=false — we don't ship dav1d's
# CLI or its test suite.
meson setup \
    --prefix="$PREFIX" \
    --libdir=lib \
    --default-library=shared \
    --buildtype=release \
    --strip \
    -Denable_tools=false \
    -Denable_tests=false \
    build
meson compile -C build -j "$JOBS"
meson install -C build

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion dav1d

cd /
rm -rf "/tmp/dav1d-${VERSION}" /tmp/dav1d.tar.bz2
