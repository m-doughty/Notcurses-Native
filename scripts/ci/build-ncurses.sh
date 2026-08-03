#!/usr/bin/env bash
# Build + install ncurses for the macOS x86_64 prebuilt lane.
# macOS ships ncurses 5.7 in /usr/lib (very old — predates notcurses'
# terminfo extension usage). Homebrew x86_64 ncurses bottles target
# macOS 14+ which fails our 10.15 deployment-target floor, so we
# source-build with MACOSX_DEPLOYMENT_TARGET=10.15 in env.
#
# Currently macOS-only. Linux manylinux_2_28 has ncurses-devel in dnf
# (the build-linux-glibc.sh path installs that directly).
#
# Configuration choices:
#   * --with-shared / --without-static — bundleable .dylibs.
#   * --enable-widec — wide-char ncurses (libncursesw), required by
#     notcurses for Unicode handling.
#   * --enable-pc-files + --with-pkg-config-libdir=$PREFIX/lib/pkgconfig
#     so cmake's pkg_search_module finds it.
#   * --with-default-terminfo-dir=/usr/share/terminfo so the shipped
#     dylib falls back to the user's system terminfo database at
#     runtime (every Intel Mac has /usr/share/terminfo populated by
#     macOS itself). We could ship our own terminfo dir but it's
#     ~5 MB of mostly-redundant data.
#   * --without-debug / --without-tests / --without-tack — strip
#     non-essential build outputs.
set -euxo pipefail

VERSION='6.5'
# ftpmirror.gnu.org redirects to a random mirror and intermittently
# 502s; retry it, then fall back to the canonical (slower) host.
URL="https://ftpmirror.gnu.org/ncurses/ncurses-${VERSION}.tar.gz"
FALLBACK_URL="https://ftp.gnu.org/gnu/ncurses/ncurses-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o ncurses.tar.gz "$URL" \
    || curl -fSL --retry 5 --retry-delay 10 -o ncurses.tar.gz "$FALLBACK_URL"
tar -xzf ncurses.tar.gz
cd "ncurses-${VERSION}"

./configure \
    --prefix="$PREFIX" \
    --with-shared \
    --without-debug \
    --without-tests \
    --without-tack \
    --without-manpages \
    --enable-widec \
    --enable-pc-files \
    --with-pkg-config-libdir="$PREFIX/lib/pkgconfig" \
    --with-default-terminfo-dir=/usr/share/terminfo \
    --without-progs \
    --without-cxx-binding \
    --without-ada

make -j"$JOBS"

# Install ONLY the libs + headers + pkg-config files. Skip
# `make install`'s default `install.data` target — that runs `tic`
# to populate $ticdir with terminfo entries, and on macOS that
# resolves to `/usr/share/terminfo` (per the configure flag above),
# which is SIP-protected and cannot be written to even by root.
# We don't need our own terminfo data anyway: every macOS install
# ships `/usr/share/terminfo` already-populated by Apple, and our
# bundled libncursesw.dylib reads from there at runtime via the
# baked-in --with-default-terminfo-dir path.
make install.libs install.includes

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion ncursesw

cd /
rm -rf "/tmp/ncurses-${VERSION}" /tmp/ncurses.tar.gz
