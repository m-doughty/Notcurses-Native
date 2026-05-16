#!/usr/bin/env bash
# Test phase of the musl verify lane — runs INSIDE the same
# alpine:3.20 container as `prep-musl-rakudo.sh`, but separated so
# a test failure doesn't bust the Rakudo build cache (Rakudo
# source-builds for ~10-20 min on first run).
#
# Assumes prep-musl-rakudo.sh already ran (Rakudo built under
# $RAKUBREW_HOME, which is bind-mounted to a host cache dir).
#
# Runs from:
#   docker run -v "$PWD:/work" -w /work \
#     -v "$PWD/_ci-cache/rakubrew-alpine-<arch>:/root/.rakubrew" \
#     -e RAKUDO_VERSION=... -e RAKUBREW_HOME=/root/.rakubrew \
#     alpine:3.20 bash scripts/ci/verify-musl-tests.sh
#
# Why source-built Rakudo (not `apk add rakudo`): Alpine's
# package-repo Rakudo lags upstream by a few minor versions and
# (as of 3.20) is too old to accept a `Callable` in NativeCall's
# `is native(...)` trait — which Notcurses::Native uses for its
# state-cached lazy lib-path resolution. apk Rakudo fails to
# precompile `Notcurses::Native::Direct` with "Too many positionals
# passed; expected 2 arguments but got 3" during `zef install`.

set -euxo pipefail

# Test-phase deps:
#   * bash, coreutils, findutils, tar, git, curl — script + zef + xt.
#   * perl, perl-utils — `prove` (Perl 5's harness) for the xt/
#     pass; matches arm64-mac reference lane.
#   * cmake, pkgconf, patchelf — source-build pass needs them.
#   * gcc, g++, musl-dev, linux-headers, make, build-base —
#     NativeCall-driven C builds inside the source-build pass.
#   * ffmpeg-dev, ncurses-dev, libunistring-dev, libdeflate-dev —
#     notcurses' build-time deps when we exercise
#     NOTCURSES_NATIVE_BUILD_FROM_SOURCE.
apk add --no-cache \
    bash coreutils findutils tar git curl ca-certificates \
    perl perl-utils build-base make \
    cmake pkgconf patchelf \
    gcc g++ musl-dev linux-headers \
    ffmpeg-dev ncurses-dev libunistring-dev libdeflate-dev

cd /work

# Install zef fresh — it's intentionally NOT in the cache (zef
# state lives in site/, and caching site/ makes `zef install`
# short-circuit on hit, skipping Build.rakumod). ~30s.
bash scripts/ci/install-zef.sh

# Put rakubrew's shims dir + zef's site-bin on PATH:
#   * shims/ — rakubrew's dispatch wrappers for raku/zef.
#   * install/share/perl6/site/bin — zef-installed module bins
#     (App::Prove6's `prove6`, etc.). rakubrew doesn't auto-rehash
#     after each `zef install` so binaries installed later in
#     this script aren't shimmed; adding site-bin to PATH
#     directly sidesteps the rehash dance.
RAKUDO_VERSION="${RAKUDO_VERSION:-2026.03}"
RAKUBREW_HOME="${RAKUBREW_HOME:-$HOME/.rakubrew}"
export PATH="$RAKUBREW_HOME/shims:$RAKUBREW_HOME/versions/moar-$RAKUDO_VERSION/install/share/perl6/site/bin:$PATH"
raku --version
zef --version

# Prebuilt path — Build.rakumod downloads
# notcurses-linux-<arch>-musl.tar.gz from the release referenced
# by BINARY_TAG, SHA-verifies it against resources/checksums.txt,
# stages to ~/.local/share/Notcurses-Native/<tag>/.
zef install --/test .
zef install --/test App::Prove6
prove6 --verbose -I lib -I t/lib t
prove -e 'raku -I lib -I t/lib' --verbose xt/*.rakutest

# Source-build path — refuse the prebuilt and exercise the CMake
# fallback. apk-installed ffmpeg/ncurses/libunistring/libdeflate
# satisfy notcurses' build deps.
NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1 zef install --/test --force-install .
prove6 --verbose -I lib -I t/lib t
