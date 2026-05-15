#!/usr/bin/env bash
# Orchestrator: build + bundle the linux-<arch>-glibc prebuilt
# notcurses archive INSIDE a manylinux2014 container. Runs from
# `docker run -v $PWD:/work -w /work quay.io/pypa/manylinux2014_<arch> bash scripts/ci/build-linux-glibc.sh`.
#
# Container directive can't be used directly because GHA's Node 24
# JS-action runtime requires glibc ≥ 2.27/2.28 + libstdc++ from
# gcc ≥ 5, and manylinux2014 ships glibc 2.17 + libstdc++ from
# devtoolset-9. So actions/checkout etc. run on the native host
# (ubuntu-22.04 / -arm) and only the build itself happens here.
#
# Cache contract: CACHE_DIR (defaulting to /work/_ci-cache/manylinux2014)
# may already contain a populated lib/ + include/ from a previous
# run's actions/cache restore. If so, skip the ~10-min ffmpeg
# source build. Otherwise build + populate.

set -euxo pipefail

CACHE_DIR="${CACHE_DIR:-/work/_ci-cache/manylinux2014}"
mkdir -p "$CACHE_DIR"

# manylinux2014 ships gcc/g++/make + python toolchains but cmake is
# too old (notcurses needs 3.21+). Install cmake3 from EPEL.
yum install -y --setopt=tsflags=nodocs \
    cmake3 pkgconfig patchelf \
    ncurses-devel libunistring-devel
ln -sf /usr/bin/cmake3 /usr/local/bin/cmake
cmake --version
ldd --version | head -1

export PKG_CONFIG_PATH="$CACHE_DIR/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$CACHE_DIR/lib:${LD_LIBRARY_PATH:-}"

# Cache-hit detection: libdeflate's pkg-config file is the cheapest
# probe (no need to invoke pkg-config). If it's there, ffmpeg's
# will be too.
if [[ -f "$CACHE_DIR/lib/pkgconfig/libdeflate.pc" \
   && -f "$CACHE_DIR/lib/pkgconfig/libavcodec.pc" ]]; then
  echo "✅ Cache hit — skipping libdeflate + ffmpeg source builds."
else
  echo "⏳ Cache miss — building libdeflate + ffmpeg from source (~10-12 min)."
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libdeflate.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-ffmpeg.sh
fi

# Verify deps resolve before kicking off notcurses build.
pkg-config --modversion libdeflate
pkg-config --modversion libavcodec libavformat libavutil libswscale libswresample

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
# $ORIGIN rpath. No EXTRA_SKIP_LIBS — default skiplist covers
# glibc's system libs.
bash scripts/ci/bundle-elf.sh

# Compile the perf shim. Linking model mirrors Vips-Native's
# shim build — link explicitly against libnotcurses-core from
# bundle/ and set DT_RUNPATH to $ORIGIN so the shim's NEEDED entry
# resolves at runtime to our patched libnotcurses-core.so at the
# same path it was compiled against, not whatever else might be
# loaded in the host process.
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
