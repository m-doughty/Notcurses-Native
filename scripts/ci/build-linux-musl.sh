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
    bash coreutils findutils tar \
    cmake make pkgconf patchelf \
    gcc g++ musl-dev linux-headers \
    ffmpeg-dev ncurses-dev libunistring-dev libdeflate-dev
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

cd vendor/notcurses
mkdir -p build
cmake -B build -S . "${CMAKE_FLAGS[@]}"
cmake --build build -j"$(nproc)"
cd ../..

# Bundle .so files + transitive ldd deps into bundle/ with
# $ORIGIN rpath. EXTRA_SKIP_LIBS keeps musl's loader / libc out of
# the archive — alpine systems already have them; bundling would
# produce a 2-libc conflict.
EXTRA_SKIP_LIBS='ld-musl-*.so.1 libc.musl-*.so.1' \
    bash scripts/ci/bundle-elf.sh

# Compile the perf shim. Same model as the glibc lane.
cc -O2 -shared -fPIC \
  -I vendor/notcurses/include \
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
