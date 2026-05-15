#!/usr/bin/env bash
# Build + install libdeflate inside a manylinux2014 container.
# RHEL 7's repos don't ship libdeflate; notcurses needs it for PNG
# decoding (via libpng → zlib-replacement layer).
#
# Honours $PREFIX (default /usr/local) so the install can target a
# workspace-relative cache dir bind-mounted into the container —
# letting actions/cache persist the build between runs.
set -euxo pipefail

VERSION='1.20'
URL="https://github.com/ebiggers/libdeflate/releases/download/v${VERSION}/libdeflate-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

cd /tmp
curl -fSL -o libdeflate.tar.gz "$URL"
tar -xzf libdeflate.tar.gz
cd "libdeflate-${VERSION}"

# CMake build — outputs shared lib + pkg-config files under
# $PREFIX. Strip the test programs (they're not needed and
# pulling them in would extend build time).
cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBDEFLATE_BUILD_SHARED_LIB=ON \
    -DLIBDEFLATE_BUILD_STATIC_LIB=OFF \
    -DLIBDEFLATE_BUILD_GZIP=OFF \
    -DLIBDEFLATE_BUILD_TESTS=OFF
cmake --build build -j"$(nproc)"
cmake --install build
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion libdeflate

cd /
rm -rf "/tmp/libdeflate-${VERSION}" /tmp/libdeflate.tar.gz
