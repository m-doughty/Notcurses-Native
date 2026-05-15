#!/usr/bin/env bash
# Build + install libdeflate. Two callers:
#   * Linux manylinux_2_28 container (RHEL 8 baseline) — RHEL 8's
#     repos don't ship libdeflate, source-build is required.
#   * macOS x86_64 Rosetta build — brew bottles target macOS 14+,
#     which fails our 10.15 deployment-target floor, so we
#     source-build with MACOSX_DEPLOYMENT_TARGET=10.15 in env.
#
# Honours $PREFIX (default /usr/local) so the install can target a
# workspace-relative cache dir, letting actions/cache persist the
# build between runs.
#
# On macOS, MACOSX_DEPLOYMENT_TARGET in env propagates through
# cmake (recognized as CMAKE_OSX_DEPLOYMENT_TARGET since cmake 3.13)
# into clang's -mmacosx-version-min, which stamps LC_BUILD_VERSION
# minos on every produced dylib.
set -euxo pipefail

VERSION='1.20'
URL="https://github.com/ebiggers/libdeflate/releases/download/v${VERSION}/libdeflate-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

# Portable parallelism: GNU nproc on Linux, sysctl on macOS, fall
# back to 4 if neither (unlikely but safe).
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

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
cmake --build build -j"$JOBS"
cmake --install build
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion libdeflate

cd /
rm -rf "/tmp/libdeflate-${VERSION}" /tmp/libdeflate.tar.gz
