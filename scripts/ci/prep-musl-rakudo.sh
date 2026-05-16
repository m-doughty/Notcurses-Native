#!/usr/bin/env bash
# Source-build Rakudo inside an alpine:3.20 container. This is the
# slow, cacheable phase of the musl verify lane — separated from
# the test phase (`verify-musl-tests.sh`) so a test failure doesn't
# invalidate the Rakudo build cache.
#
# Runs from:
#   docker run -v "$PWD:/work" -w /work \
#     -v "$PWD/_ci-cache/rakubrew-alpine-<arch>:/root/.rakubrew" \
#     -e RAKUDO_VERSION=... -e RAKUBREW_HOME=/root/.rakubrew \
#     alpine:3.20 bash scripts/ci/prep-musl-rakudo.sh
#
# Idempotent — build-rakudo.sh short-circuits when ~/.rakubrew
# already contains a built moar-${RAKUDO_VERSION}.

set -euxo pipefail

# Minimal deps just for the Rakudo build. The test phase installs
# the full set later (cmake, pkgconf, patchelf, ffmpeg-dev, etc.).
apk add --no-cache \
    bash coreutils findutils tar git curl ca-certificates \
    perl build-base make

cd /work
bash scripts/ci/build-rakudo.sh
