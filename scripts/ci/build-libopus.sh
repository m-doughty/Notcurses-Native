#!/usr/bin/env bash
# Build + install libopus — Xiph's Opus audio codec. Linked into our
# source-built ffmpeg via --enable-libopus so Opus audio decode
# (common in modern web video tracks) has the same accelerated path
# users get on package-managed lanes.
#
# Honours $PREFIX (default /usr/local). Honours $MACOSX_DEPLOYMENT_TARGET
# on macOS — libopus's autotools configure passes it through to
# clang.
set -euxo pipefail

VERSION='1.5.2'
URL="https://github.com/xiph/opus/releases/download/v${VERSION}/opus-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 --retry-all-errors -o opus.tar.gz "$URL"
tar -xzf opus.tar.gz
cd "opus-${VERSION}"

# --disable-doc — no html/man output.
# --disable-extra-programs — opusdec, opusenc CLIs (we link the
# library, not the binaries).
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-extra-programs
make -j"$JOBS"
make install

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion opus

cd /
rm -rf "/tmp/opus-${VERSION}" /tmp/opus.tar.gz
