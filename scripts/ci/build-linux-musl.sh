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
#
# Why the codec stack is source-built here rather than `apk add
# ffmpeg-dev`: Alpine's ffmpeg is a GPL build. Its libavcodec has
# DT_NEEDEDs on libx264, libx265, libSvtAv1Enc, libmp3lame and
# libxvidcore, and `avutil_license()` reports "GPL version 3 or
# later" — so bundle-elf.sh's ldd walk dragged that entire encoder
# chain into the archive we publish, making the two musl prebuilts
# GPL-encumbered (for a library that only ever decodes) and much
# fatter than they needed to be. Building the same LGPL-2.1,
# decoder-only ffmpeg the glibc and macOS lanes already use puts
# every shipped lane on identical codec surface.
# build-ffmpeg.sh asserts the LGPL license line at configure time so
# this can't silently regress.
#
# libdeflate is source-built for the same reason the glibc lane does
# it — not licensing (it's MIT), but so that all four lanes ship the
# same pinned version rather than whatever the distro froze. Alpine
# 3.20's is 1.20; build-libdeflate.sh pins 1.25.
#
# Cache contract: CACHE_DIR (defaulting to /work/_ci-cache/alpine-3.20)
# may already contain a populated lib/ + include/ from a previous
# run's actions/cache restore. If so, skip the ~15-min codec source
# build. Otherwise build + populate. Same contract as
# build-linux-glibc.sh.
#
# DEPS_ONLY=1 stops the script right after that codec chain is ready
# (chowning $CACHE_DIR back to the host user first) instead of going
# on to build notcurses. _build-linux-musl.yml runs this script
# twice on a cache miss — once with DEPS_ONLY=1, so it can save the
# actions/cache entry immediately afterwards, before anything that
# can still fail; once without, to do the notcurses build against the
# now-warm cache. See the DEPS_ONLY branch below for why.

set -euxo pipefail

CACHE_DIR="${CACHE_DIR:-/work/_ci-cache/alpine-3.20}"
mkdir -p "$CACHE_DIR"

# Alpine doesn't pre-install ANY toolchain — bash isn't even there
# until we apk add it. The docker-run invocation can use sh as the
# entry shell, but we want bash for the build to match the script
# header.
#
#   * curl / xz / bzip2: the source-build scripts fetch with
#     `curl -fSL` and unpack .tar.xz (ffmpeg) + .tar.bz2 (dav1d).
#     Alpine's base image has neither curl nor GNU tar, and GNU tar
#     shells out to the xz / bzip2 binaries for those two.
#   * meson + ninja: libdav1d's build system. Alpine's `ninja`
#     package is samurai, a ninja-compatible reimplementation
#     providing /usr/bin/ninja — which is what Alpine builds dav1d
#     with itself, and what meson drives here.
#   * perl: libvpx's configure/build generates its assembly
#     offsets + version header through perl scripts.
#   * diffutils: libvpx's configure probes `diff --version` and
#     hard-fails ("diff missing: Try installing diffutils via your
#     package manager.") on busybox's applet, which doesn't
#     implement --version. It's a real dependency, not just a
#     version probe — the build diffs generated asm offsets.
#   * zlib-dev: ffmpeg's png decoder has a hard `zlib` dependency,
#     so --enable-decoder=png fails configure without the headers.
#     Came in transitively via ffmpeg-dev before; now explicit.
#
# libunistring-dev is deliberately absent. It is LGPL and it ships
# inside the pack, so we have to be able to hand a user the exact
# corresponding source for the binary they got — which an apk package
# version that moves under us cannot do. It is source-built into
# $CACHE_DIR below from a pinned, SHA-256-recorded tarball.
# ncurses-dev stays: MIT-style X11, no source-conveyance duty, and
# its terminfo-directory configuration makes a source build fiddly.
APK_PKGS=(
    bash coreutils findutils diffutils tar git
    curl xz bzip2
    cmake make pkgconf patchelf
    meson ninja perl
    gcc g++ musl-dev linux-headers
    zlib-dev ncurses-dev
)
# nasm / yasm assemble x86 SIMD and nothing else — dav1d, libvpx and
# ffmpeg all use ARM-native GAS assembly on aarch64, which gcc
# handles. Installing them on the aarch64 lane would be asking for
# packages that lane can't use; build-ffmpeg.sh's own nasm gate is
# x86-only for the same reason.
case "$(uname -m)" in
    x86_64|amd64|i[3-6]86) APK_PKGS+=(nasm yasm) ;;
esac
apk add --no-cache "${APK_PKGS[@]}"

# Fetch notcurses source from the pinned NOTCURSES_FORK SHA. Cache
# under /work/_ci-cache so actions/cache on the host can persist
# the checkout. Same SHA-keyed path Build.rakumod uses for the
# install-time source-build fallback.
export NOTCURSES_SRC_CACHE="${NOTCURSES_SRC_CACHE:-/work/_ci-cache/notcurses-source}"
NOTCURSES_SRC_DIR=$(bash scripts/ci/fetch-notcurses-source.sh)
export NOTCURSES_SRC_DIR
cmake --version
meson --version
ninja --version
# No `ldd --version` on musl; the loader prints its info if invoked
# directly, but only as a side-effect.
/lib/ld-musl-*.so.1 --version 2>&1 | head -2 || true

# Point every lookup mechanism at the codec cache prefix. Same five
# variables the glibc lane exports, for the same reasons:
#   * PKG_CONFIG_PATH — how ffmpeg's configure finds dav1d/vpx/opus,
#     and how notcurses' CMakeLists finds libav*.
#   * LD_LIBRARY_PATH — so the linker-produced binaries (and
#     bundle-elf.sh's ldd walk) can resolve the .so files before
#     they've been copied into bundle/.
#   * CMAKE_PREFIX_PATH — CMake's find_path / find_library /
#     find_package don't read PKG_CONFIG_PATH, and notcurses locates
#     libdeflate via a raw find_path, so without this it bails with
#     "Couldn't find libdeflate.h" despite libdeflate sitting in
#     $CACHE_DIR/include.
#   * CPATH / LIBRARY_PATH — defensive, for the places notcurses'
#     build invokes cc/ld outside CMake's find_X-managed flag set
#     (the perf-shim compile at the bottom of this script is exactly
#     that case).
export PKG_CONFIG_PATH="$CACHE_DIR/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$CACHE_DIR/lib:${LD_LIBRARY_PATH:-}"
export CMAKE_PREFIX_PATH="$CACHE_DIR:${CMAKE_PREFIX_PATH:-}"
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

# Escape hatch for the cache-split pattern the workflow uses:
# _build-linux-musl.yml runs this script ONCE with DEPS_ONLY=1 to
# populate (or, on a cache hit, merely verify) $CACHE_DIR, saves the
# actions/cache entry off the back of THAT docker run, and only then
# runs this script a second time — cache warm — for the notcurses
# build below. Splitting the docker invocation is what makes the
# save actually happen: within a single `docker run`, a later
# failure (notcurses build, bundling, the codec probe) would abort
# the whole GHA step before a combined actions/cache action's post-
# job save step ever gets to run, discarding the ~15-20 min codec
# build that had already succeeded — which is exactly what happened
# to the Windows lane in the r10 dispatch that motivated this split.
#
# chown here, not just at the very end of a full run: on the
# DEPS_ONLY invocation this IS the end of the run, and $CACHE_DIR is
# the one artefact the following host-side `actions/cache/save` step
# needs to read — root-owned (this container runs as root against
# the /work bind mount) is unreadable-enough to matter there, same
# failure class as fix 2's bundle/ permission error.
if [[ "${DEPS_ONLY:-}" == "1" ]]; then
  chown -R "$(stat -c '%u:%g' /work)" "$CACHE_DIR"
  echo "✅ DEPS_ONLY=1 — codec chain is ready in \$CACHE_DIR; skipping notcurses build."
  exit 0
fi

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
  # CMAKE_PREFIX_PATH first and /usr/lib after, and alpine can still
  # acquire a libunistring.so as a transitive apk dependency of
  # something else — in which case cmake would happily link that one
  # while bundle-elf.sh copies whichever the runtime loader picks.
  # Same class of check as the Windows lane's DEFLATE:FILEPATH
  # assertion. awk-with-exit rather than `grep | head -1`: head
  # closing the pipe SIGPIPEs its producer and `set -o pipefail`
  # turns that into a mystery failure.
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

# Release gate: confirm bundled libavcodec actually got linked
# against libdav1d / libvpx / libopus during ffmpeg's configure, and
# that PNG / JPEG / BMP really decode. Catches the regression class
# where pkg-config silently failed and ffmpeg fell back to its
# internal decoders. If the probe fails, the build job fails, and
# release.yml's `needs:` chain refuses to publish this artefact.
bash scripts/ci/run-codec-probe.sh

# This container runs as root against the /work bind mount, so
# everything it created under /work — bundle/ above all — comes out
# root-owned on the host. package-and-upload's emit-third-party-kit.sh
# step runs AFTER this script, on the host, as the unprivileged
# runner user, and needs to create bundle/LICENSES: root-owned,
# group/other-writable-less directories made that a permission
# denied rather than a licensing-kit write. Restore host ownership
# before handing control back. $CACHE_DIR is included too, for the
# benefit of a standalone `docker run ... build-linux-musl.sh`
# invocation that never went through the DEPS_ONLY split above (the
# split path already chowned it at that point, so this is a no-op
# there) — anything else this script writes under /work
# (_ci-cache/notcurses-source, populated by fetch-notcurses-source.sh)
# is container-read-only from here on and never written to by a
# host-side step, so it does not need the same treatment.
chown -R "$(stat -c '%u:%g' /work)" /work/bundle "$CACHE_DIR"
