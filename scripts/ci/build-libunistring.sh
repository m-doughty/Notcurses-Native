#!/usr/bin/env bash
# Build + install libunistring for the macOS x86_64 prebuilt lane.
# Homebrew x86_64 libunistring bottles target macOS 14+ which fails
# our 10.15 deployment-target floor, so we source-build with
# MACOSX_DEPLOYMENT_TARGET=10.15 in env.
#
# Currently macOS-only. Linux manylinux_2_28 has libunistring-devel
# in dnf (the build-linux-glibc.sh path installs that directly).
set -euxo pipefail

VERSION='1.3'
URL="https://ftpmirror.gnu.org/libunistring/libunistring-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL -o libunistring.tar.gz "$URL"
tar -xzf libunistring.tar.gz
cd "libunistring-${VERSION}"

# --enable-shared / --disable-static — match the rest of the bundle.
# clang reads $MACOSX_DEPLOYMENT_TARGET, stamps the dylib's
# LC_BUILD_VERSION minos accordingly.
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static

make -j"$JOBS"
make install

# libunistring doesn't ship a pkg-config file by default; just verify
# the dylib exists.
ls -la "$PREFIX/lib/libunistring."* | head -5

cd /
rm -rf "/tmp/libunistring-${VERSION}" /tmp/libunistring.tar.gz
