#!/usr/bin/env bash
# Build + install ffmpeg. Two callers:
#   * Linux manylinux_2_28 container (RHEL 8 baseline) — RHEL 8's
#     repos don't ship ffmpeg, source-build is required.
#   * macOS x86_64 Rosetta build — brew bottles target macOS 14+,
#     which fails our 10.15 deployment-target floor, so we
#     source-build with MACOSX_DEPLOYMENT_TARGET=10.15 in env. clang
#     reads $MACOSX_DEPLOYMENT_TARGET and stamps LC_BUILD_VERSION
#     minos on every produced dylib.
#
# Config is intentionally minimal: shared libs, no executables, no
# devices, only the codecs notcurses might encounter when decoding
# user-provided images. Keeping the surface tight controls bundle
# size (full ffmpeg adds ~80 MB; this targets ~25 MB).
#
# Honours $PREFIX (default /usr/local) so the install can target a
# workspace-relative cache dir, letting actions/cache persist the
# build between runs.
set -euxo pipefail

VERSION='6.1.2'
URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

# Make sure pkg-config finds the source-built codec libs we depend
# on (libdav1d, libvpx, libopus, libdeflate). Their .pc files were
# installed by their respective build scripts into $PREFIX/lib/pkgconfig.
# Defensive export — build-linux-glibc.sh already exports this in
# its env, but the macOS workflow step invokes us directly without
# setting it.
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# Portable parallelism: GNU nproc on Linux, sysctl on macOS.
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# nasm is needed for x86 SIMD — caller MUST pre-install it before
# invoking this script, because the codec libs we now also build
# (libdav1d, libvpx) need nasm too and the caller orchestrates the
# order. Concretely:
#   * manylinux_2_28: build-linux-glibc.sh `dnf install nasm` in
#     its system-deps step.
#   * macOS x86_64: _build-macos.yml's "Install build deps" step
#     runs `arch -x86_64 /usr/local/bin/brew install nasm`.
# Bail out loudly if anything skipped that step.
if ! command -v nasm >/dev/null 2>&1; then
    echo "❌ nasm not on PATH." >&2
    echo "   Caller must install nasm before invoking build-ffmpeg.sh:" >&2
    echo "     * manylinux: dnf install -y nasm" >&2
    echo "     * macOS: arch -x86_64 /usr/local/bin/brew install nasm" >&2
    exit 1
fi

cd /tmp
curl -fSL --retry 5 --retry-delay 10 --retry-all-errors -o ffmpeg.tar.xz "$URL"
tar -xJf ffmpeg.tar.xz
cd "ffmpeg-${VERSION}"

# Configure flags:
#   --disable-{static,doc,debug}    → smaller, faster build
#   --enable-shared                 → bundle-able .so files
#   --disable-programs              → no ffmpeg/ffprobe binaries
#   --disable-{decoder,encoder,muxer,demuxer,parser,bsf,protocol,filter}
#                                   → start from empty, enable only what we need
#   --enable-decoder=...            → image + audio for notcurses' use cases
#   --enable-{demuxer,protocol}=... → matching containers + file:/data:/pipe:
#   --enable-zlib                   → PNG via zlib
#   --enable-libxml2 omitted        → DASH manifest support unneeded
#   --enable-pic                    → required for shared lib on x86_64
# Accelerated codec libs the caller is expected to have already
# source-built into $PREFIX:
#   * libdav1d → ~10× faster AV1 decode (the big win).
#   * libvpx   → VP8/9 decode (marginal win, but matches what
#                package-managed lanes ship).
#   * libopus  → Opus audio decode (marginal win, parity).
# --enable-libfoo enables the libfoo-dispatched codecs; the matching
# --enable-decoder=libdav1d / libvpx_vp9 / libopus selects the libfoo
# decoder over the internal one when codec_id matches at runtime.
#
# --disable-lzma / --disable-bzlib / --disable-libxml2: these are
# all auto-enabled by ffmpeg's configure if their .pc files are
# visible via pkg-config. Our PKG_CONFIG_PATH prepends $PREFIX/
# lib/pkgconfig but doesn't block the default fallback paths
# (/usr/local/lib/pkgconfig on Intel-mac brew, /usr/lib/pkgconfig
# on Linux), so on a runner with brew xz installed, ffmpeg would
# transparently link against /usr/local/Cellar/xz/.../liblzma.5.dylib
# — a brew bottle targeting macOS 14+, which fails our 10.15
# deployment-target audit. Explicitly disable to force ffmpeg to
# ignore these even when found. We don't need any of them for the
# image/video formats notcurses cares about: lzma is for rare
# matroska variants, bzip2 for similarly rare cases, libxml2 for
# DASH/manifest demuxers.
./configure \
    --prefix="$PREFIX" \
    --libdir="$PREFIX/lib" \
    --pkg-config-flags=--static \
    --disable-static \
    --enable-shared \
    --enable-pic \
    --disable-doc \
    --disable-debug \
    --disable-programs \
    --disable-everything \
    --disable-lzma \
    --disable-bzlib \
    --disable-libxml2 \
    --enable-avformat \
    --enable-avcodec \
    --enable-avutil \
    --enable-avdevice \
    --enable-swscale \
    --enable-swresample \
    --enable-zlib \
    --enable-libdav1d \
    --enable-libvpx \
    --enable-libopus \
    --enable-decoder=png,mjpeg,jpegls,jpeg2000,bmp,gif,webp,tiff,tga,pcx,pbm,pgm,ppm,pam \
    --enable-decoder=mp3,aac,vorbis,flac,opus,pcm_s16le,pcm_s16be,pcm_u8 \
    --enable-decoder=h264,hevc,vp8,vp9,av1,mpeg4,theora \
    --enable-decoder=libdav1d,libvpx_vp8,libvpx_vp9,libopus \
    --enable-demuxer=image2,mjpeg,gif,mov,matroska,mp3,wav,ogg,flac,aac \
    --enable-parser=png,mjpeg,h264,hevc,vp8,vp9,av1,mpegaudio,aac \
    --enable-protocol=file,pipe,data
make -j"$JOBS"
make install

# ldconfig only matters on Linux when PREFIX=/usr/local (the linker's
# default search path). For workspace-prefix installs OR macOS,
# the caller is expected to set LD_LIBRARY_PATH / DYLD_LIBRARY_PATH /
# PKG_CONFIG_PATH to find these.
if [[ "$PREFIX" == "/usr/local" ]] && command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion libavcodec libavformat libavutil libswscale libswresample

cd /
rm -rf "/tmp/ffmpeg-${VERSION}" /tmp/ffmpeg.tar.xz
