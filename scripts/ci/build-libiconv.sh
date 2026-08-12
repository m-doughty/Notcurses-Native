#!/usr/bin/env bash
# Build + install GNU libiconv — the character-set conversion library
# the Windows packs carry because there is no iconv(3) in the Windows
# C runtime.
#
# ONLY the two Windows lanes call this. glibc, musl and libSystem all
# provide iconv inside libc, so on Linux and macOS nothing ever links
# GNU libiconv and no pack there contains one. On MSYS2 there is no
# iconv in the CRT at all, so two of the libraries we build go looking
# for one and link it when they find it:
#
#   * ffmpeg — its configure autodetects iconv (`check_func_headers
#     iconv.h iconv || check_lib iconv iconv.h iconv -liconv`) and
#     puts it on avcodec's link line. avcodec-<N>.dll in the r10 packs
#     imports libiconv-2.dll.
#   * libunistring — its AM_ICONV links GNU libiconv whenever the
#     toolchain carries one, exactly as build-libunistring.sh's header
#     predicted. libunistring-5.dll imports it too.
#
# A PE import scan of both published r10 Windows packs found those two
# and nothing else — notably NOT ncursesw, which is the other
# package-managed library in the pack. So every importer of
# libiconv-2.dll is a binary we build ourselves, which is what makes
# source-building it a self-contained change rather than an attempt to
# out-run the toolchain's own package closure.
#
# WHY IT IS SOURCE-BUILT, and not just taken from pacman. libiconv is
# LGPL-2.1-or-later and it ships inside the .zip, so conveying it
# obliges us to be able to hand a recipient the corresponding source
# for the exact binary they received. `pacman -S
# mingw-w64-*-libiconv` cannot answer that: MSYS2 moves its package
# versions under us and garbage-collects the old builds off the
# mirrors, so "the source for the libiconv-2.dll in this archive"
# stops being answerable a few months after any given release. That is
# the identical argument that moved libunistring onto the self-built
# chain, and it is recorded against this component in
# resources/third-party.json with a pinned URL + SHA-256 that
# .github/workflows/_release-publish.yml attaches to every binary
# release.
#
# MSYS2's own libiconv package stays installed either way — it is in
# the toolchain group's dependency closure and cannot be removed — and
# its DLL has the identical basename, so path priority is the whole
# game. build-libunistring.sh and build-ffmpeg.sh both point their
# configures at $PREFIX explicitly when this script has populated it,
# and _build-windows.yml re-checks after bundling that the
# libiconv-2.dll which landed in the pack is byte-identical to the one
# staged here.
#
# Plain autotools. Honours $PREFIX (default /usr/local) so the install
# can target a workspace-relative cache dir that actions/cache
# persists between runs.
#
# Platform notes:
#   * SONAME major is 2 and has been for the whole modern series
#     (lib/Makefile.in pins -version-info 9:1:7, and 9 - 7 = 2), so
#     the shipped file is libiconv-2.dll. The belt-and-braces sweep
#     list in .github/actions/bundle-dll and the Windows basename
#     pattern in resources/third-party.json both spell that major out
#     — grep for `libiconv-2` before bumping to anything that changes
#     it.
#   * `make install` also installs libcharset (libcharset-1.dll, from
#     -version-info 1:0:0) and the iconv(1) program. Neither reaches a
#     pack: libiconv.la compiles ../libcharset/lib/localcharset.c
#     straight into libiconv.la rather than linking -lcharset, so
#     libiconv-2.dll imports no libcharset at all, and bundle-dll
#     copies DLLs by import or by its curated sweep list, never by
#     "everything in $PREFIX/bin".
#   * mingw needs windres to compile windows/libiconv.rc into the DLL
#     (configure.ac makes it unconditional for host_os=mingw*). UCRT64
#     gets it from binutils; CLANGARM64 gets a `windres` shim from
#     mingw-w64-clang-aarch64-llvm-tools, which the toolchain group
#     already installs — the same package that supplies objdump / nm /
#     dlltool under their GNU names there. No arch-specific configure
#     flag is needed on either lane.
#   * We deliberately do NOT carry MSYS2's three downstream patches.
#     Two of them (the configure.all CR fix, the cp65001 alias) only
#     matter to a build that regenerates the gperf tables via
#     Makefile.devel, which a release tarball build does not. The
#     third rewrites lib/iconv.c's `(int)(long)&((struct
#     stringpool2_t *)0)->…` offsets to `(int)(intptr_t)`; on LLP64
#     that cast truncates a pointer to 32 bits, which both gcc and
#     clang accept in a static initialiser with a
#     -Wpointer-to-int-cast warning (verified against clang in C mode)
#     — and the offsets involved are a few kilobytes, so nothing is
#     actually lost. Patching would matter more than the warning does:
#     the tarball whose SHA-256 we publish as the corresponding source
#     is the pristine one, so a locally-patched build would make that
#     claim false. The warning is silenced below instead.
set -euxo pipefail

# 1.19 — current stable. SHA-256 recorded in
# resources/third-party.json and cross-checked against MSYS2's own
# mingw-w64-libiconv PKGBUILD, which pins the same tarball.
VERSION='1.19'
# ftpmirror.gnu.org redirects to a random mirror and intermittently
# 502s; retry it, then fall back to the canonical (slower) host. Both
# spellings serve byte-identical tarballs — the SHA-256 recorded in
# resources/third-party.json is checked against whichever answered.
URL="https://ftpmirror.gnu.org/libiconv/libiconv-${VERSION}.tar.gz"
FALLBACK_URL="https://ftp.gnu.org/gnu/libiconv/libiconv-${VERSION}.tar.gz"
PREFIX="${PREFIX:-/usr/local}"
mkdir -p "$PREFIX"

# Portable parallelism: GNU nproc on Linux, sysctl on macOS, fall
# back to 4 if neither.
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# -O2 because naming CFLAGS at all suppresses autoconf's own `-g -O2`
# default, and an unoptimised iconv would be a silly thing to ship.
# -Wno-pointer-to-int-cast because of the sysdep-alias table described
# in the header: on LLP64 (both Windows lanes) it truncates a pointer
# to `long`, which is noisy but harmless, and which upstream fixes
# only in git. Written as a warning suppression rather than a source
# patch so the tarball we publish as corresponding source stays the
# one we built. Both gcc and clang know the flag.
export CFLAGS="${CFLAGS:-} -O2 -Wno-pointer-to-int-cast"

cd /tmp
curl -fSL --retry 5 --retry-delay 10 -o libiconv.tar.gz "$URL" \
    || curl -fSL --retry 5 --retry-delay 10 -o libiconv.tar.gz "$FALLBACK_URL"
tar -xzf libiconv.tar.gz
cd "libiconv-${VERSION}"

# --enable-shared / --disable-static — a bundleable DLL, matching
# every other library in the pack.
#
# --disable-nls is load-bearing, not a size tweak. libiconv's
# configure runs AM_GNU_GETTEXT([external]), so with NLS left on it
# links GNU gettext's libintl-8.dll — and dropping libintl out of the
# packs is half the point of this change. The r10 packs shipped
# libintl-8.dll as pure over-collection: a PE import scan found
# nothing importing it, it was in the bundle only because the
# belt-and-braces sweep named it. It is LGPL and package-manager
# sourced, i.e. the same unpinnable-corresponding-source problem this
# script exists to remove, so it is now swept out of the bundle AND
# denied by resources/third-party.json (which has no entry for it, and
# the audit gate fails closed on any file no component describes).
# Source-building a libiconv that dragged it straight back in would be
# a comic outcome; --disable-nls is what stops that, and the objdump
# check after `make install` proves it stayed stopped. All this costs
# is translated error strings from the iconv(1) program we do not
# ship.
#
# Deliberately NOT passed, both of which MSYS2's package does pass:
#   * --enable-extra-encodings — a handful of rarely used legacy
#     codepages. Nothing in a pack can reach them: ffmpeg's only iconv
#     caller is the subtitle charset converter, and this is a
#     --disable-everything decoder build with no subtitle demuxer or
#     decoder enabled at all, while notcurses uses libunistring's
#     unistr/unigbrk/unictype/uniwbrk and never its uniconv module. It
#     also switches on the sysdep-alias table for every OS at once,
#     which is where the pointer-truncation warning above comes from.
#   * --enable-relocatable — for finding charset.alias relative to the
#     installed binary. On native Windows localcharset.c does not read
#     charset.alias at all (it derives the codepage from the Win32
#     API), so it buys nothing here, and libiconv 1.19's NEWS opens
#     with "Fixed --enable-relocatable on native Windows", which is
#     not a feature to opt into on the strength of one release.
./configure \
    --prefix="$PREFIX" \
    --enable-shared \
    --disable-static \
    --disable-nls

make -j"$JOBS"
make install

# libiconv ships no pkg-config file of its own (MSYS2's package adds
# one downstream; upstream does not), so there is no `pkg-config
# --modversion` self-check to make like the codec scripts do. Verify
# the artefacts the consumers actually need instead, and fail loudly
# if any is missing — a silent half-install here surfaces much later
# as ffmpeg's configure quietly deciding it has no iconv, or as
# libunistring linking the pacman copy we are trying to stop shipping.
missing=0
if [[ ! -f "$PREFIX/include/iconv.h" ]]; then
    echo "::error::libiconv install left no \$PREFIX/include/iconv.h"
    missing=1
fi
# The linkable artefact: libiconv.dll.a (import lib, with the DLL in
# bin/) on mingw, libiconv.so.N / libiconv.N.dylib elsewhere. `find`
# rather than a glob so an unmatched pattern is a count of 0 rather
# than a literal-string test.
if [[ $(find "$PREFIX/lib" -maxdepth 1 -name 'libiconv.*' | wc -l) -eq 0 ]]; then
    echo "::error::libiconv install left nothing matching \$PREFIX/lib/libiconv.*"
    missing=1
fi
if (( missing != 0 )); then
    echo "❌ libiconv ${VERSION} did not install into $PREFIX as expected."
    ls -la "$PREFIX/lib" "$PREFIX/include" 2>/dev/null || true
    exit 1
fi

# Windows-only shape + NLS assertions. libtool installs the DLL under
# $PREFIX/bin and the import library under $PREFIX/lib, the same split
# ffmpeg's mingw32 target and libunistring use.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        dll="$PREFIX/bin/libiconv-2.dll"
        if [[ ! -f "$dll" ]]; then
            echo "❌ No \$PREFIX/bin/libiconv-2.dll after install."
            echo "   Either libtool changed where it puts the DLL, or the"
            echo "   SONAME major moved off 2 (-version-info 9:1:7 in"
            echo "   lib/Makefile.in). Both the bundle-dll sweep list and"
            echo "   the Windows pattern in resources/third-party.json"
            echo "   name libiconv-2.dll exactly, so either would ship an"
            echo "   unaudited DLL. Contents of \$PREFIX/bin:"
            ls -la "$PREFIX/bin" 2>/dev/null || true
            exit 1
        fi
        # --disable-nls, proven rather than trusted: if libintl is on
        # this DLL's import table then the pack would carry
        # libintl-8.dll again — a package-manager-sourced LGPL library
        # with no corresponding source, which is exactly the gap this
        # script closes. objdump is present on both lanes (binutils on
        # UCRT64, llvm-tools on CLANGARM64); if it somehow is not, say
        # so loudly rather than passing silently.
        if command -v objdump >/dev/null 2>&1; then
            imports=$(objdump -p "$dll" | awk '/DLL Name:/{print $3}' \
                        | tr '[:upper:]' '[:lower:]')
            echo "--- libiconv-2.dll imports ---"
            printf '%s\n' "$imports"
            if grep -q 'libintl' <<< "$imports"; then
                echo "❌ libiconv-2.dll imports libintl — --disable-nls did not"
                echo "   take effect. Fix the configure line; do not add"
                echo "   libintl back to the bundle."
                exit 1
            fi
        else
            echo "::warning::objdump not on PATH — could not verify that"
            echo "libiconv-2.dll links no libintl."
        fi
        ;;
esac

echo "--- installed libiconv artefacts ---"
find "$PREFIX/lib" "$PREFIX/bin" -maxdepth 1 -name 'libiconv*' 2>/dev/null || true

cd /
rm -rf "/tmp/libiconv-${VERSION}" /tmp/libiconv.tar.gz
