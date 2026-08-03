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
# ftpmirror.gnu.org redirects to a random mirror and intermittently
# 502s; retry it, then fall back to the canonical (slower) host.
URL="https://ftpmirror.gnu.org/libunistring/libunistring-${VERSION}.tar.gz"
FALLBACK_URL="https://ftp.gnu.org/gnu/libunistring/libunistring-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 --retry-all-errors -o libunistring.tar.gz "$URL" \
    || curl -fSL --retry 5 --retry-delay 10 --retry-all-errors -o libunistring.tar.gz "$FALLBACK_URL"
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
# the dylib exists. `|| true` to tolerate SIGPIPE under pipefail
# (head exits after line 5 closing stdin; ls writes more = SIGPIPE).
ls -la "$PREFIX/lib/libunistring."* | head -5 || true

cd /
rm -rf "/tmp/libunistring-${VERSION}" /tmp/libunistring.tar.gz
