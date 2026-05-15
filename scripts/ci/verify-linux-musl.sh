#!/usr/bin/env bash
# Verify the linux-<arch>-musl prebuilt notcurses archive loads + works
# INSIDE an alpine:3.20 container. Runs from
# `docker run -v $PWD:/work -w /work alpine:3.20 bash scripts/ci/verify-linux-musl.sh`.
#
# Same docker-run reasoning as build-linux-musl.sh — JS actions
# (Raku/setup-raku, actions/checkout) can't run in alpine, so the
# native host does checkout and dispatches into this script.
#
# Tests both install paths:
#   1. Prebuilt: zef install --/test .   (proves the archive loads +
#      its symbols resolve self-contained against musl).
#   2. Source-build: NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1 reinstall
#      (proves Build.rakumod's CMake fallback works on musl with the
#      apk-supplied ffmpeg/ncurses/etc.).

set -euxo pipefail

# Alpine doesn't ship Raku/zef by default. The apk packages are a
# few releases behind upstream Rakudo but that's fine for verify
# purposes — we're testing "does the binary load + do basic things
# work", not Rakudo-version-specific behaviour.
#
# Build deps are needed for the source-build pass below — install
# them all upfront so the container only does one apk roundtrip.
apk add --no-cache \
    bash coreutils findutils tar git \
    rakudo zef \
    cmake make pkgconf patchelf \
    gcc g++ musl-dev linux-headers \
    ffmpeg-dev ncurses-dev libunistring-dev libdeflate-dev

cd /work

# Prebuilt path — Build.rakumod downloads
# notcurses-linux-<arch>-musl.tar.gz from the release referenced
# by BINARY_TAG, SHA-verifies it against resources/checksums.txt,
# stages to ~/.local/share/Notcurses-Native/<tag>/.
zef install --/test .
zef install --/test App::Prove6
prove6 --verbose -I lib -I t/lib t

# Source-build path — refuse the prebuilt and exercise the CMake
# fallback. apk-installed ffmpeg/ncurses/libunistring/libdeflate
# satisfy notcurses' build deps.
NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1 zef install --/test --force-install .
prove6 --verbose -I lib -I t/lib t
