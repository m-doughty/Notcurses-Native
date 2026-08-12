#!/usr/bin/env bash
# Orchestrator: build + bundle the linux-<arch>-glibc prebuilt
# notcurses archive INSIDE a manylinux_2_28 container. Runs from
# `docker run -v $PWD:/work -w /work quay.io/pypa/manylinux_2_28_<arch> bash scripts/ci/build-linux-glibc.sh`.
#
# manylinux_2_28 = RHEL 8 baseline = glibc 2.28. Successor to
# manylinux2014 (CentOS 7, glibc 2.17) which pypa retired March 2025
# and whose mirrors decay after the June 2024 CentOS 7 EOL. Floor
# of 2.28 still covers RHEL 8+ / Ubuntu 18.10+ / Debian 10+ — i.e.
# every glibc distro under active maintenance in 2026.
#
# Cache contract: CACHE_DIR (defaulting to /work/_ci-cache/manylinux_2_28)
# may already contain a populated lib/ + include/ from a previous
# run's actions/cache restore. If so, skip the ~10-min ffmpeg
# source build. Otherwise build + populate.

set -euxo pipefail

CACHE_DIR="${CACHE_DIR:-/work/_ci-cache/manylinux_2_28}"
mkdir -p "$CACHE_DIR"

# Fetch notcurses source from the pinned NOTCURSES_FORK SHA.
# manylinux_2_28 ships git, so no apk/dnf install needed first.
# Set NOTCURSES_SRC_CACHE under /work so actions/cache on the host
# can persist the checkout across runs (same key bumping rules as
# the ffmpeg cache — keyed on the SHA itself).
export NOTCURSES_SRC_CACHE="${NOTCURSES_SRC_CACHE:-/work/_ci-cache/notcurses-source}"
NOTCURSES_SRC_DIR=$(bash scripts/ci/fetch-notcurses-source.sh)
export NOTCURSES_SRC_DIR

# System packages via dnf:
#   * pkgconfig, patchelf, ncurses-devel: base build/runtime needs.
#   * nasm, yasm: needed by libdav1d / libvpx / ffmpeg for x86 SIMD
#     (on aarch64 they're no-ops but cheap to install).
# RHEL 8 doesn't ship modern ffmpeg / libdeflate / libdav1d / libvpx /
# libopus — those get source-built below into $CACHE_DIR with
# accelerated paths (--enable-libdav1d in ffmpeg, etc.) so notcurses
# gets ~10× faster AV1 decode + matched VP8/9 + Opus accel.
#
# libunistring-devel is deliberately NOT here any more. It is LGPL
# and it ships inside the pack, so we need to be able to point at the
# exact source for the binary we handed the user — which a dnf
# package version that moves under us cannot do. It is source-built
# into $CACHE_DIR below from a pinned, SHA-256-recorded tarball. (As
# a side effect the packs move from RHEL 8's libunistring.so.2 to
# libunistring.so.5.) ncurses stays package-managed: it is MIT-style
# X11 with no source-conveyance duty, and its terminfo-directory
# configuration makes a source build genuinely fiddly.
dnf install -y --setopt=tsflags=nodocs \
    pkgconfig patchelf \
    nasm yasm \
    ncurses-devel

# cmake / meson / ninja via pip — RHEL 8's dnf ships cmake 3.20 and
# notcurses needs 3.21+. meson + ninja are required by libdav1d's
# build system. manylinux preinstalls Python at /opt/python/cp*/bin/;
# the pip wheels for all three are current.
PYBIN=$(ls -d /opt/python/cp3*/bin 2>/dev/null | head -1)
[[ -n "$PYBIN" ]] || { echo "❌ No /opt/python/cp3*/bin found in manylinux image"; exit 1; }
"$PYBIN/pip" install --quiet cmake meson ninja
ln -sf "$PYBIN/cmake" /usr/local/bin/cmake
ln -sf "$PYBIN/meson" /usr/local/bin/meson
ln -sf "$PYBIN/ninja" /usr/local/bin/ninja
cmake --version
meson --version
ninja --version
# `| head -1` is informational; tolerate SIGPIPE under `set -o
# pipefail` (head closes stdin after line 1, ldd's continuing
# version-blob writes then SIGPIPE — bash propagates exit 141 and
# kills the script otherwise).
ldd --version | head -1 || true

export PKG_CONFIG_PATH="$CACHE_DIR/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$CACHE_DIR/lib:${LD_LIBRARY_PATH:-}"
# CMake's find_path / find_library / find_package don't read
# PKG_CONFIG_PATH — they search CMAKE_PREFIX_PATH plus system dirs.
# notcurses' CMakeLists.txt locates libdeflate via a raw find_path
# (not pkg-config like it does for ffmpeg), so without this it
# bails with "Couldn't find libdeflate.h" even though libdeflate
# is sitting in $CACHE_DIR/include.
export CMAKE_PREFIX_PATH="$CACHE_DIR:${CMAKE_PREFIX_PATH:-}"
# CPATH for raw `cc -I` resolution, LIBRARY_PATH for the linker's
# `-l` lookup — defensive in case notcurses' build invokes the
# compiler outside of CMake's find_X-managed flag set.
export CPATH="$CACHE_DIR/include:${CPATH:-}"
export LIBRARY_PATH="$CACHE_DIR/lib:${LIBRARY_PATH:-}"

# Cache-hit detection: ffmpeg's pkg-config file is the cheapest
# all-or-nothing probe. ffmpeg is the LAST thing built, so if it's
# present every prerequisite (libdeflate, libdav1d, libvpx, libopus)
# is too.
if [[ -f "$CACHE_DIR/lib/pkgconfig/libavcodec.pc" ]]; then
  echo "✅ Cache hit — skipping libunistring / libdeflate / libdav1d / libvpx / libopus / ffmpeg builds."
else
  # Codec libs MUST land before ffmpeg — ffmpeg's configure probes
  # them via pkg-config + --enable-libfoo to wire its libfoo-backed
  # decoder dispatches. libunistring is independent of all of them
  # (notcurses links it directly, ffmpeg never sees it); it goes
  # first only so the cache-hit probe below — which keys on ffmpeg,
  # the last thing built — still implies everything else is present.
  echo "⏳ Cache miss — building accelerated codec stack from source (~15-20 min first run)."
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libunistring.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libdeflate.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libdav1d.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libvpx.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-libopus.sh
  PREFIX="$CACHE_DIR" bash scripts/ci/build-ffmpeg.sh
fi

# Verify deps resolve before kicking off notcurses build.
pkg-config --modversion libdeflate
pkg-config --modversion dav1d vpx opus
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

(
  cd "$NOTCURSES_SRC_DIR"
  mkdir -p build
  cmake -B build -S . "${CMAKE_FLAGS[@]}"
  # Assert notcurses linked OUR libunistring, not a stray system one.
  # `find_library(unistring unistring REQUIRED)` searches
  # CMAKE_PREFIX_PATH first and /usr/lib64 after, and this container
  # can still acquire a libunistring.so as a transitive dnf
  # dependency of something else — in which case cmake would happily
  # link the distro's 0.9.9 while bundle-elf.sh copies whichever the
  # runtime loader picks. Same class of check as the Windows lane's
  # DEFLATE:FILEPATH assertion. awk-with-exit rather than
  # `grep | head -1`: head closing the pipe SIGPIPEs its producer and
  # `set -o pipefail` turns that into a mystery failure.
  unistring_lib=$(awk -F= '/^unistring:FILEPATH=/{print $2; exit}' build/CMakeCache.txt)
  case "$unistring_lib" in
    "$CACHE_DIR"/*)
      echo "ok: unistring resolved to $unistring_lib" ;;
    *)
      echo "❌ find_library(unistring) resolved to '$unistring_lib',"
      echo "   which is outside the source-built prefix '$CACHE_DIR'."
      echo "   The pack would ship a libunistring we never built,"
      echo "   pinned, or recorded a source tarball for."
      exit 1 ;;
  esac
  cmake --build build -j"$(nproc)"
)

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

# Release gate: confirm libavcodec actually got linked against
# libdav1d / libvpx / libopus during ffmpeg's configure. Catches
# the regression class where pkg-config silently failed and ffmpeg
# fell back to its internal decoders. If the probe fails, the
# build job fails, and release.yml's `needs:` chain refuses to
# publish this artefact.
bash scripts/ci/run-codec-probe.sh
