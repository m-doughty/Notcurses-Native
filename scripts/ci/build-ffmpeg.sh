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

# Portable parallelism: GNU nproc on Linux, sysctl on macOS.
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# nasm is needed for x86 SIMD. Available paths:
#   * Linux manylinux_2_28: yum (dnf) — try first, fall back to
#     building from source if EPEL is unavailable.
#   * macOS: assume caller pre-installed nasm via x86_64 brew (the
#     workflow does this in its "Install build tools" step). Bail
#     out loudly if it isn't on PATH.
if ! command -v nasm >/dev/null 2>&1; then
    if command -v yum >/dev/null 2>&1; then
        yum install -y --setopt=tsflags=nodocs yasm nasm zlib-devel bzip2-devel xz-devel || {
            # EPEL nasm sometimes isn't reachable; build from source.
            NASM_V='2.16.03'
            curl -fSL -o /tmp/nasm.tar.xz \
                "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_V}/nasm-${NASM_V}.tar.xz"
            (cd /tmp && tar -xJf nasm.tar.xz \
                && cd "nasm-${NASM_V}" \
                && ./configure --prefix=/usr/local \
                && make -j"$JOBS" \
                && make install)
            rm -rf "/tmp/nasm-${NASM_V}" /tmp/nasm.tar.xz
        }
    else
        echo "❌ nasm not on PATH and no yum/dnf available." >&2
        echo "   On macOS, install via x86_64 brew: arch -x86_64 /usr/local/bin/brew install nasm" >&2
        exit 1
    fi
fi

cd /tmp
curl -fSL -o ffmpeg.tar.xz "$URL"
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
    --enable-avformat \
    --enable-avcodec \
    --enable-avutil \
    --enable-avdevice \
    --enable-swscale \
    --enable-swresample \
    --enable-zlib \
    --enable-decoder=png,mjpeg,jpegls,jpeg2000,bmp,gif,webp,tiff,tga,pcx,pbm,pgm,ppm,pam \
    --enable-decoder=mp3,aac,vorbis,flac,opus,pcm_s16le,pcm_s16be,pcm_u8 \
    --enable-decoder=h264,hevc,vp8,vp9,av1,mpeg4,theora \
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
