#!/usr/bin/env bash
# Build + install GNU libunistring — the Unicode string library
# notcurses uses for grapheme-cluster segmentation (unigbrk.h),
# word breaking (uniwbrk.h) and character property lookups
# (unictype.h). notcurses' CMakeLists.txt hard-requires it:
# `find_path(unigbrk.h)` + `find_library(unistring unistring REQUIRED)`,
# with a FATAL_ERROR if either misses.
#
# All four platforms source-build it now. It was the last
# package-manager-sourced LGPL library left in the shipped packs, and
# package-manager sourcing means we cannot point a user at the exact
# corresponding source for the binary we handed them: dnf/apk/brew/
# pacman all move their package versions under us and garbage-collect
# old builds, so "the source for the libunistring.so.5 in this
# archive" would have been unanswerable a few months after any given
# release. libunistring is LGPL-3.0-or-later OR GPL-2.0-or-later and
# we convey it under the LGPL, which obliges us to be able to hand
# over that source. A pinned tarball + recorded SHA-256 in
# resources/third-party.json makes that answerable for good:
#
#   * Linux manylinux_2_28 — was `dnf install libunistring-devel`
#     (0.9.9, so the packs shipped libunistring.so.2).
#   * Linux alpine 3.20 — was `apk add libunistring-dev`.
#   * macOS arm64 — was `brew install libunistring`. macOS x86_64
#     already source-built it here, because brew's x86_64 bottles
#     target macOS 14+ and would fail that lane's 10.15
#     deployment-target audit.
#   * Windows MSYS2 — was `pacman -S mingw-w64-*-libunistring`.
#
# Plain autotools, no unusual configure surface. Honours $PREFIX
# (default /usr/local) so the install can target a workspace-relative
# cache dir that actions/cache persists between runs, and honours
# $MACOSX_DEPLOYMENT_TARGET on macOS — libtool passes it through to
# clang, which stamps LC_BUILD_VERSION minos on the produced dylib.
#
# Platform notes:
#   * SONAME major is 5 for the whole 1.x series (lib/Makefile.am
#     pins -version-info 7:R:2, and 7 - 2 = 5), so the shipped file
#     is libunistring.so.5 / libunistring.5.dylib / libunistring-5.dll.
#     Bumping to a libunistring 2.x would change that, and the
#     belt-and-braces sweep list in .github/actions/bundle-dll plus
#     the basename patterns in resources/third-party.json both spell
#     the major out — grep for `libunistring-5` before bumping.
#   * MSYS2/mingw: libtool installs the DLL under $PREFIX/bin and the
#     import library under $PREFIX/lib, the same split ffmpeg's
#     mingw32 target uses. `find_library(unistring unistring)`
#     consumes $PREFIX/lib/libunistring.dll.a; bundle-dll picks the
#     DLL up out of $PREFIX/bin via its extra-search-path.
#   * iconv is deliberately left to configure's own detection rather
#     than forced either way. glibc, musl and libSystem all provide
#     iconv in libc, so the POSIX lanes never link GNU libiconv. On
#     MSYS2 there is no iconv in the C runtime, so libunistring links
#     mingw's libiconv if pacman happens to have it installed (it
#     arrives transitively) and builds its uniconv module as a stub
#     if not. Either outcome is fine here: notcurses uses unistr /
#     unigbrk / unictype / uniwbrk and never touches uniconv.
set -euxo pipefail

# 1.4.2 — current stable.
VERSION='1.4.2'
# ftpmirror.gnu.org redirects to a random mirror and intermittently
# 502s; retry it, then fall back to the canonical (slower) host.
# Both spellings serve byte-identical tarballs — the SHA-256 recorded
# in resources/third-party.json is checked against whichever answered.
URL="https://ftpmirror.gnu.org/libunistring/libunistring-${VERSION}.tar.gz"
FALLBACK_URL="https://ftp.gnu.org/gnu/libunistring/libunistring-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

# Portable parallelism: GNU nproc on Linux, sysctl on macOS, fall
# back to 4 if neither.
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o libunistring.tar.gz "$URL" \
    || curl -fSL --retry 5 --retry-delay 10 -o libunistring.tar.gz "$FALLBACK_URL"
tar -xzf libunistring.tar.gz
cd "libunistring-${VERSION}"

# --enable-shared / --disable-static — bundleable .so / .dylib / .dll,
# matching every other library in the pack. libunistring has no NLS
# and no --disable-doc equivalent worth passing; the docs it installs
# are info/man pages under $PREFIX/share, which nothing bundles.
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static

make -j"$JOBS"
make install

# libunistring ships no pkg-config file, so there is no
# `pkg-config --modversion` self-check to make like the codec
# scripts do. Verify the two artefacts the consumers actually need
# instead, and fail loudly if either is missing — a silent
# half-install here surfaces ten minutes later as notcurses' cmake
# saying "Couldn't find unigbrk.h from GNU libunistring", with no
# hint that this script is where it went wrong.
missing=0
if [[ ! -f "$PREFIX/include/unigbrk.h" ]]; then
    echo "::error::libunistring install left no \$PREFIX/include/unigbrk.h"
    missing=1
fi
# The linkable artefact: libunistring.so.N / libunistring.N.dylib on
# POSIX, libunistring.dll.a (import lib, with the DLL in bin/) on
# mingw. `find` rather than a glob so an unmatched pattern is a
# count of 0 rather than a literal-string test.
if [[ $(find "$PREFIX/lib" -maxdepth 1 -name 'libunistring.*' | wc -l) -eq 0 ]]; then
    echo "::error::libunistring install left nothing matching \$PREFIX/lib/libunistring.*"
    missing=1
fi
if (( missing != 0 )); then
    echo "❌ libunistring ${VERSION} did not install into $PREFIX as expected."
    ls -la "$PREFIX/lib" "$PREFIX/include" 2>/dev/null || true
    exit 1
fi
echo "--- installed libunistring artefacts ---"
find "$PREFIX/lib" "$PREFIX/bin" -maxdepth 1 -name 'libunistring*' 2>/dev/null || true

cd /
rm -rf "/tmp/libunistring-${VERSION}" /tmp/libunistring.tar.gz
