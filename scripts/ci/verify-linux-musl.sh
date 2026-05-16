#!/usr/bin/env bash
# Verify the linux-<arch>-musl prebuilt notcurses archive loads +
# works INSIDE an alpine:3.20 container. Runs from
# `docker run -v $PWD:/work -w /work alpine:3.20 bash scripts/ci/verify-linux-musl.sh`.
#
# Why source-build Rakudo instead of `apk add rakudo`: Alpine's
# package-repo Rakudo lags upstream by a few minor versions and
# (as of 3.20) is too old to accept a `Callable` in NativeCall's
# `is native(...)` trait — which Notcurses::Native uses for its
# state-cached lazy lib-path resolution. apk Rakudo fails to
# precompile `Notcurses::Native::Direct` with "Too many positionals
# passed; expected 2 arguments but got 3" during `zef install`.
# Source-built current Rakudo via rakubrew handles the modern
# Callable-native signature correctly.
#
# Caller is expected to:
#   * Bind-mount $PWD to /work (workspace).
#   * Set RAKUDO_VERSION (matches the cache key).
#   * Optionally bind-mount /root/.rakubrew to a host cache dir.

set -euxo pipefail

# Build deps:
#   * bash, coreutils, findutils, tar, git, curl — script + zef.
#   * perl, build-base, make — rakubrew's Configure.pl + Rakudo
#     build (gcc, ld, etc.).
#   * cmake, pkgconf, patchelf — for the source-build pass.
#   * ffmpeg-dev + ncurses-dev + libunistring-dev + libdeflate-dev —
#     notcurses' build-time deps when we exercise
#     NOTCURSES_NATIVE_BUILD_FROM_SOURCE.
#   * linux-headers, musl-dev — needed for any C compile inside
#     the container.
apk add --no-cache \
    bash coreutils findutils tar git curl \
    perl perl-utils build-base make \
    cmake pkgconf patchelf \
    gcc g++ musl-dev linux-headers \
    ffmpeg-dev ncurses-dev libunistring-dev libdeflate-dev

# perl-utils ships `prove` (Perl 5's test harness). The arm64-mac
# reference lane runs `prove -e 'raku -I lib -I t/lib' xt/*.rakutest`
# for terminal-dependent tests; we mirror that here so every
# non-Windows lane has the same coverage.

cd /work

# Source-build Rakudo (idempotent — short-circuits if already
# built from a cached $RAKUBREW_HOME).
bash scripts/ci/build-rakudo.sh

# Put rakubrew's shims dir + zef's site-bin on PATH:
#   * shims/ — rakubrew's dispatch wrappers for raku/zef (set up
#     by build-rakudo.sh).
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
