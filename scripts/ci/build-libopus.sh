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

# 1.6.1 — current stable.
#
# URL note: xiph stopped attaching dist tarballs to their GitHub
# releases after 1.5.2 (v1.6/v1.6.1 exist as tags with no assets), and
# GitHub's auto-generated tag tarball is a bare git export with no
# `configure` — it would need autogen.sh plus the full autotools
# chain on every runner. downloads.xiph.org is upstream's own
# distribution point and carries the proper dist tarball; it 302s to
# an osuosl mirror, which `curl -fSL` follows.
VERSION='1.6.1'
URL="https://downloads.xiph.org/releases/opus/opus-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o opus.tar.gz "$URL"
tar -xzf opus.tar.gz
cd "opus-${VERSION}"

# --disable-doc — no html/man output.
# --disable-extra-programs — opusdec, opusenc CLIs (we link the
# library, not the binaries).
extra_flags=()

# opus's ARM runtime CPU detection (rtcd) has backends for Linux
# (/proc/cpuinfo), Apple and MSVC — and none for mingw/clang on
# Windows ARM64, where celt/arm/armcpu.c stops the build with its own
# #error naming this flag. Disabling rtcd there is safe, not a
# compromise: NEON is architecturally baseline on aarch64, so the
# compile-time paths are always valid; the only loss is optional
# runtime dispatch to dotprod/i8mm extensions, which matters to
# nobody decoding audio in a terminal.
if [[ "${MSYSTEM_CARCH:-}" == 'aarch64' ]]; then
    extra_flags+=('--disable-rtcd')
fi

./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-extra-programs \
    ${extra_flags[@]+"${extra_flags[@]}"}
make -j"$JOBS"
make install

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion opus

cd /
rm -rf "/tmp/opus-${VERSION}" /tmp/opus.tar.gz
