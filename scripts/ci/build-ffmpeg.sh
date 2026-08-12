#!/usr/bin/env bash
# Build + install ffmpeg. Four callers:
#   * Linux manylinux_2_28 container (RHEL 8 baseline) — RHEL 8's
#     repos don't ship ffmpeg, source-build is required.
#   * macOS x86_64 Rosetta build — brew bottles target macOS 14+,
#     which fails our 10.15 deployment-target floor, so we
#     source-build with MACOSX_DEPLOYMENT_TARGET=10.15 in env. clang
#     reads $MACOSX_DEPLOYMENT_TARGET and stamps LC_BUILD_VERSION
#     minos on every produced dylib.
#   * macOS arm64 native build — brew's ffmpeg formula is a GPL
#     build (--enable-gpl plus x264/x265/SvtAv1Enc/lame/rubberband),
#     so bundling its dylibs made the macos-arm64 prebuilt archive
#     GPL-encumbered for a library that only ever decodes. Source-
#     building here keeps every shipped lane on the same LGPL-2.1,
#     decoder-only ffmpeg (and drops the encoder chain from the
#     bundle entirely).
#   * Windows MSYS2 {UCRT64,CLANGARM64} — for exactly the same
#     licensing reason as macOS arm64: MSYS2's mingw-w64-*-ffmpeg is
#     a `--enable-gpl --enable-version3` build carrying x264, x265,
#     SvtAv1Enc, lame, rubberband and friends, and bundle-dll swept
#     that whole encoder tree into the shipped .zip. Source-building
#     here puts Windows on the identical LGPL-2.1 decode-only surface
#     as the other three platforms.
#
# Windows/MSYS2 notes (they surprise people coming from the POSIX
# lanes; each is asserted below rather than assumed):
#   * ffmpeg's mingw32 target sets shlibdir=bindir and SLIBPREF="",
#     so the shared objects install as $PREFIX/bin/avcodec-62.dll,
#     NOT $PREFIX/lib/libavcodec.so.62. The import libraries
#     ($PREFIX/lib/libavcodec.dll.a) are what the linker consumes.
#     Anything downstream that globs $PREFIX/lib for shared objects
#     will come up empty on Windows — look in $PREFIX/bin.
#   * `uname -m` lies on MSYS2: msys2-runtime is an x86_64 Cygwin
#     fork even when it is running under emulation on a Windows-on-ARM
#     host, so it reports x86_64 on the CLANGARM64 lane whose clang
#     emits aarch64. MSYSTEM_CARCH is the honest signal and ffmpeg's
#     own configure prefers it (`arch_default="$MSYSTEM_CARCH"`).
#
# Config is intentionally minimal: shared libs, no executables, no
# devices, only the codecs notcurses might encounter when decoding
# user-provided images. Keeping the surface tight controls bundle
# size (full ffmpeg adds ~80 MB; this targets ~25 MB).
#
# LICENSING IS LOAD-BEARING: no --enable-gpl, no --enable-nonfree, no
# encoders. These dylibs ship inside a prebuilt archive for an
# Artistic-2.0 distribution, so a GPL ffmpeg would relicense the
# archive out from under users. The assertion after ./configure below
# fails the build if the reported license is anything other than
# "LGPL version 2.1 or later" — if it ever fires, the question is a
# licensing decision, not a build flag.
#
# Honours $PREFIX (default /usr/local) so the install can target a
# workspace-relative cache dir, letting actions/cache persist the
# build between runs.
set -euxo pipefail

# 8.1.2 — newest point release on the 8.1 branch. ffmpeg 9.0 is out
# but we deliberately stay a series behind: 8.1 is the branch the
# distros and brew are shipping, so it's the one with the most
# eyeballs on it, and a decode-only surface gains nothing from a
# brand-new major. Revisit when 9.x has a couple of point releases.
#
# Fetched from ffmpeg's own GitHub mirror rather than ffmpeg.org:
# the first r10 CI dispatch saw connection timeouts/resets against
# ffmpeg.org from multiple GitHub-hosted runners (reproduced locally
# too — not a one-off blip), and ffmpeg.org carries no CDN fronting,
# so a single upstream host being flaky takes every lane down with
# it. GitHub's tag archive is a legitimate substitute here (unlike a
# bare source snapshot from most projects) because ffmpeg checks
# `configure` into git — it's not an autotools output that only a
# `make dist` tarball would carry. TAG uses ffmpeg's own release-tag
# convention (`n` + version, e.g. `n8.1.2`); VERSION stays bare
# because it also names this script's install layout below and is
# what t/17 cross-checks resources/third-party.json against.
VERSION='8.1.2'
TAG="n${VERSION}"
URL="https://github.com/FFmpeg/FFmpeg/archive/refs/tags/${TAG}.tar.gz"
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
#   * manylinux_2_28 x86_64: build-linux-glibc.sh `dnf install nasm`
#     in its system-deps step.
#   * macOS x86_64: _build-macos.yml's "Install build deps" step
#     runs `arch -x86_64 /usr/local/bin/brew install nasm`.
#   * Windows UCRT64: _build-windows.yml's pacman list carries
#     mingw-w64-ucrt-x86_64-nasm.
# Bail out loudly if an x86 caller skipped that step.
#
# The requirement is x86-only: nasm assembles x86/x86_64 SIMD and
# nothing else. On aarch64/arm64 (macOS arm64 native, manylinux
# aarch64, MSYS2 CLANGARM64) ffmpeg, dav1d and libvpx all use
# ARM-native inline/GAS assembly the C compiler handles, so demanding
# nasm there would make the arm64 lanes install a package they can't
# use.
#
# Arch detection precedence, and why it isn't just `uname -m`:
#   * $MSYSTEM_CARCH first. MSYS2 exports it (x86_64 under UCRT64,
#     aarch64 under CLANGARM64) and it tracks the *toolchain*, which
#     is what decides whether ffmpeg emits x86 asm. `uname -m` under
#     MSYS2 reports the arch of msys2-runtime — an x86_64 Cygwin fork
#     that runs emulated on Windows-on-ARM — so on the CLANGARM64
#     lane it says x86_64 while clang targets aarch64. Trusting it
#     there would demand a nasm the build never invokes. ffmpeg's own
#     configure uses exactly this precedence, so our gate and its asm
#     selection can't disagree.
#   * `uname -m` otherwise, which is correct everywhere else —
#     including under `arch -x86_64` on Apple Silicon, where it
#     reports x86_64, which is exactly the Rosetta case we DO want
#     gated.
BUILD_ARCH="${MSYSTEM_CARCH:-$(uname -m)}"
case "$BUILD_ARCH" in
    x86_64|amd64|i[3-6]86)
        if ! command -v nasm >/dev/null 2>&1; then
            echo "❌ nasm not on PATH (required for x86 SIMD)." >&2
            echo "   Caller must install nasm before invoking build-ffmpeg.sh:" >&2
            echo "     * manylinux: dnf install -y nasm" >&2
            echo "     * macOS: arch -x86_64 /usr/local/bin/brew install nasm" >&2
            echo "     * MSYS2:  pacman -S mingw-w64-ucrt-x86_64-nasm" >&2
            exit 1
        fi
        ;;
    *)
        echo "Non-x86 build arch ($BUILD_ARCH) — skipping the nasm requirement." >&2
        ;;
esac

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o ffmpeg.tar.gz "$URL"
tar -xzf ffmpeg.tar.gz
# GitHub's tag-archive top-level dir is `<org-repo-casing>-<tag>`, so
# `FFmpeg-n8.1.2` here — not `ffmpeg-${VERSION}` the way ffmpeg.org's
# own release tarball was named.
cd "FFmpeg-${TAG}"

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
# Component-name note (ffmpeg 8.x re-verified, 2026-08): every name
# in the allowlists below was checked against `./configure
# --list-{decoders,demuxers,parsers,protocols}` for 8.1.2. ffmpeg's
# configure treats an unmatched --enable-decoder=X as a WARNING, not
# an error ("Option --enable-decoder=tga did not match anything"), so
# a wrong name silently ships a bundle missing that decoder. One such
# typo was live here: the Truevision TGA decoder is called `targa`,
# never `tga` (`tga` is only ever the file extension), so TGA images
# were never actually decodable despite being listed. Fixed below.
# If you add a name, confirm it against --list-decoders first and
# watch the configure output for "did not match anything".
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
#
# --disable-xlib / --disable-libxcb / --disable-sdl2 /
# --disable-vulkan / --disable-libdrm: same class of problem, found
# when the macOS arm64 lane moved to source-build. These are all
# [autodetect] and all serve components we've already switched off
# (x11grab, the sdl2 outdev, Vulkan/DRM hwaccel), but autodetection
# still puts them on the LINK line: on a host with brew's libxcb
# installed, libavcodec came out with LC_LOAD_DYLIBs on
# /opt/homebrew/opt/libx11, libxcb, libxau and libxdmcp. dylibbundler
# would then drag the whole X11 stack into the archive we ship. The
# bundle is supposed to be a function of these scripts, not of what
# happens to be installed on the runner — pin them off explicitly.
# Apple's own frameworks (VideoToolbox, AudioToolbox, CoreImage,
# AppKit, AVFoundation, SecureTransport) are deliberately left on:
# they live under /System, so they add no file to the bundle, and
# VideoToolbox buys hardware-accelerated h264/hevc decode for free.
#
# configure's output is tee'd to $configure_log so the two assertions
# below can read it back: an unmatched component name and a non-LGPL
# license line are both "build succeeded, artefact is wrong" failures
# that no later step would notice. `set -o pipefail` (top of file)
# keeps configure's own exit status authoritative through the tee.
configure_log="/tmp/ffmpeg-${VERSION}-configure.log"
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
    --disable-xlib \
    --disable-libxcb \
    --disable-sdl2 \
    --disable-vulkan \
    --disable-libdrm \
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
    --enable-decoder=png,mjpeg,jpegls,jpeg2000,bmp,gif,webp,tiff,targa,pcx,pbm,pgm,ppm,pam \
    --enable-decoder=mp3,aac,vorbis,flac,opus,pcm_s16le,pcm_s16be,pcm_u8 \
    --enable-decoder=h264,hevc,vp8,vp9,av1,mpeg4,theora \
    --enable-decoder=libdav1d,libvpx_vp8,libvpx_vp9,libopus \
    --enable-demuxer=image2,mjpeg,gif,mov,matroska,mp3,wav,ogg,flac,aac \
    --enable-parser=png,mjpeg,h264,hevc,vp8,vp9,av1,mpegaudio,aac \
    --enable-protocol=file,pipe,data 2>&1 | tee "$configure_log"

# Assertion 1: every --enable-{decoder,demuxer,parser,protocol} name
# matched a real component. ffmpeg only warns on a miss, so without
# this a renamed component (they do get renamed across majors) ships
# a bundle that quietly can't decode that format.
if grep -q 'did not match anything' "$configure_log"; then
    echo "❌ ffmpeg configure ignored one or more component names:" >&2
    grep 'did not match anything' "$configure_log" >&2
    echo "   Check the name against ./configure --list-decoders etc." >&2
    exit 1
fi

# Assertion 2: the build is LGPL. Every lane ships these dylibs
# inside our prebuilt archive, and Notcurses::Native is Artistic-2.0
# — a GPL ffmpeg (--enable-gpl, or a nonfree codec) would relicense
# the whole archive out from under users. If this ever fires, the
# question is a licensing decision, not a build flag.
if ! grep -q '^License: LGPL version 2.1 or later' "$configure_log"; then
    echo "❌ ffmpeg configure did not report an LGPL-2.1+ license:" >&2
    grep -i '^License:' "$configure_log" >&2 || echo "   (no License: line at all)" >&2
    exit 1
fi

# Assertion 3 (MSYS2 only): configure resolved the same architecture
# the toolchain actually targets. ffmpeg reads $MSYSTEM_CARCH for its
# arch default, so this can only diverge if MSYS2 stopped exporting it
# (configure would silently fall back to `uname -m` = x86_64 and try
# to assemble x86 SIMD with an aarch64 clang) or if a caller passed a
# conflicting --arch. Both are "configure succeeded, artefact is for
# the wrong CPU" failures that nothing downstream would notice until a
# user's LoadLibrary fails.
if [[ -n "${MSYSTEM_CARCH:-}" ]]; then
    ff_arch=$(awk '/^ARCH[[:space:]]/{print $2; exit}' "$configure_log")
    if [[ "$ff_arch" != "$MSYSTEM_CARCH" ]]; then
        echo "❌ ffmpeg configured for ARCH='$ff_arch' but MSYSTEM_CARCH='$MSYSTEM_CARCH'." >&2
        echo "   The produced DLLs would not match the MSYS2 environment's toolchain." >&2
        exit 1
    fi
fi

make -j"$JOBS"
make install

# Assertion 4 (MSYS2 only): the install landed in Windows shape.
# ffmpeg's `mingw32` target block is what sets shlibdir=bindir,
# SLIBPREF="" and SLIBSUF=".dll"; if configure had failed to normalise
# `uname -s` (MINGW64_NT-…) onto that target it would happily produce
# ELF-shaped libavcodec.so.62 files in $PREFIX/lib and every later
# step — bundle-dll's DLL glob, the codec probe's avcodec-*.dll
# lookup — would report a confusing "missing" rather than "wrong
# target OS". Assert the shape directly instead of parsing configure's
# output for a target-os line it never prints.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        dll_count=$(find "$PREFIX/bin" -maxdepth 1 -name 'avcodec-*.dll' -type f 2>/dev/null | wc -l)
        if (( dll_count == 0 )); then
            echo "❌ No \$PREFIX/bin/avcodec-*.dll after install — ffmpeg did not" >&2
            echo "   build for target-os=mingw32. Contents of \$PREFIX:" >&2
            ls -la "$PREFIX/bin" "$PREFIX/lib" >&2 || true
            exit 1
        fi
        if [[ ! -f "$PREFIX/lib/libavcodec.dll.a" ]]; then
            echo "❌ Missing \$PREFIX/lib/libavcodec.dll.a import library —" >&2
            echo "   nothing downstream can link against this ffmpeg." >&2
            ls -la "$PREFIX/lib" >&2 || true
            exit 1
        fi
        ;;
esac

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
rm -rf "/tmp/FFmpeg-${TAG}" /tmp/ffmpeg.tar.gz "$configure_log"
