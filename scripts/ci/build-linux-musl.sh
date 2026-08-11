#!/usr/bin/env bash
# Orchestrator: build + bundle the linux-<arch>-musl prebuilt
# notcurses archive INSIDE an alpine:3.20 container. Runs from
# `docker run -v $PWD:/work -w /work alpine:3.20 bash scripts/ci/build-linux-musl.sh`.
#
# Container directive can't be used directly because:
#   * GHA's Node 24 JS-action runtime is built against glibc;
#     alpine ships musl, so JS actions (checkout, upload-artifact)
#     can't run inside the container at all.
#   * On aarch64, GHA explicitly errors with "JavaScript Actions in
#     Alpine containers are only supported on x64 Linux runners".
#
# So actions/checkout etc. run on the native host (ubuntu-22.04 or
# -arm) and only the build itself happens here.
#
# musl ABI is stable in the 1.2.x series — building on alpine:3.20
# (musl 1.2.5) produces binaries that load on any musl 1.2.x runtime
# (Alpine 3.13+, Postmarket OS, Void, Adelie).

set -euxo pipefail

# Alpine doesn't pre-install ANY toolchain — bash isn't even there
# until we apk add it. The docker-run invocation can use sh as the
# entry shell, but we want bash for the build to match the script
# header.
apk add --no-cache \
    bash coreutils findutils tar git \
    cmake make pkgconf patchelf \
    gcc g++ musl-dev linux-headers \
    ffmpeg-dev ncurses-dev libunistring-dev libdeflate-dev

# Fetch notcurses source from the pinned NOTCURSES_FORK SHA. Cache
# under /work/_ci-cache so actions/cache on the host can persist
# the checkout. Same SHA-keyed path Build.rakumod uses for the
# install-time source-build fallback.
export NOTCURSES_SRC_CACHE="${NOTCURSES_SRC_CACHE:-/work/_ci-cache/notcurses-source}"
NOTCURSES_SRC_DIR=$(bash scripts/ci/fetch-notcurses-source.sh)
export NOTCURSES_SRC_DIR
cmake --version
# No `ldd --version` on musl; the loader prints its info if invoked
# directly, but only as a side-effect.
/lib/ld-musl-*.so.1 --version 2>&1 | head -2 || true

CMAKE_FLAGS=(
  -DUSE_MULTIMEDIA=ffmpeg
  -DBUILD_FFI_LIBRARY=ON
  -DUSE_CXX=OFF
  -DBUILD_EXECUTABLES=OFF
  -DUSE_PANDOC=OFF
  -DUSE_DOCTEST=OFF
  -DUSE_POC=OFF
  -DUSE_STATIC=OFF
  -DCMAKE_BUILD_TYPE=Release
)

(
  cd "$NOTCURSES_SRC_DIR"
  mkdir -p build
  cmake -B build -S . "${CMAKE_FLAGS[@]}"
  cmake --build build -j"$(nproc)"
)

# Bundle .so files + transitive ldd deps into bundle/ with
# $ORIGIN rpath. EXTRA_SKIP_LIBS keeps musl's loader / libc out of
# the archive — alpine systems already have them; bundling would
# produce a 2-libc conflict.
EXTRA_SKIP_LIBS='ld-musl-*.so.1 libc.musl-*.so.1' \
    bash scripts/ci/bundle-elf.sh

# Compile the perf shim. Same model as the glibc lane.
cc -O2 -shared -fPIC \
  -I "$NOTCURSES_SRC_DIR/include" \
  -Wl,-soname,libnotcurses_native_shim.so \
  -o bundle/libnotcurses_native_shim.so \
  src/notcurses_native_shim.c \
  -Lbundle -lnotcurses-core
patchelf --set-rpath '$ORIGIN' bundle/libnotcurses_native_shim.so
echo "--- shim symbols ---"
nm -g --defined-only bundle/libnotcurses_native_shim.so \
  | grep -E 'T (_)?notcurses_native_' || {
    echo "❌ no notcurses_native_* exports — link silently failed."
    exit 1
  }
# Sidecar for Build.rakumod's content-based freshness check: the
# SHA-256 of the shim source this shim was compiled from. Without
# it, installs fall back to a cross-machine mtime comparison that
# always thinks the dist's source is newer than the packed shim
# and recompiles (or, toolchain-less, warns and drops to the slow
# per-cell path).
sha256sum src/notcurses_native_shim.c | awk '{print $1}' \
  > bundle/libnotcurses_native_shim.so.srchash

# Release gate: confirm bundled libavcodec has the required
# accelerated decoders (libdav1d, libvpx_vp8, libvpx_vp9, libopus).
# Alpine's ffmpeg-dev package usually has all of them, but a future
# apk update could drop a feature; the probe blocks publish if so.
bash scripts/ci/run-codec-probe.sh
