#!/usr/bin/env bash
# Build + install ffmpeg inside a manylinux2014 container.
# RHEL 7's repos don't ship ffmpeg; notcurses' multimedia path
# (image rendering — Selkie/Cantina avatars depend on this) requires
# libavformat + libavcodec + libavutil + libswscale + libswresample.
#
# Config is intentionally minimal: shared libs, no executables, no
# devices, only the codecs notcurses might encounter when decoding
# user-provided images. Keeping the surface tight controls bundle
# size (full ffmpeg adds ~80 MB; this targets ~25 MB).
#
# Honours $PREFIX (default /usr/local) so the install can target a
# workspace-relative cache dir bind-mounted into the container —
# letting actions/cache persist the build between runs.
set -euxo pipefail

VERSION='6.1.2'
URL="https://ffmpeg.org/releases/ffmpeg-${VERSION}.tar.xz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

# Need nasm for x86 SIMD; not available in manylinux2014 base.
# Build from source (~1 min, cheap relative to ffmpeg itself).
yum install -y --setopt=tsflags=nodocs yasm nasm zlib-devel bzip2-devel xz-devel || {
    # nasm sometimes isn't in the default repos; build from source.
    cd /tmp
    NASM_V='2.16.03'
    curl -fSL -o nasm.tar.xz "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_V}/nasm-${NASM_V}.tar.xz"
    tar -xJf nasm.tar.xz
    (cd "nasm-${NASM_V}" && ./configure --prefix=/usr/local && make -j"$(nproc)" && make install)
    rm -rf "/tmp/nasm-${NASM_V}" /tmp/nasm.tar.xz
}

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
make -j"$(nproc)"
make install

# ldconfig only matters when PREFIX=/usr/local (the linker's default
# search path). For workspace-prefix installs, the caller is
# expected to set LD_LIBRARY_PATH + PKG_CONFIG_PATH to find these.
if [[ "$PREFIX" == "/usr/local" ]]; then
    ldconfig
fi
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --modversion libavcodec libavformat libavutil libswscale libswresample

cd /
rm -rf "/tmp/ffmpeg-${VERSION}" /tmp/ffmpeg.tar.xz
