#!/usr/bin/env bash
# Build + install the macOS x86_64 lanes' build TOOLCHAIN — cmake,
# ninja, meson, pkg-config (pkgconf), nasm and dylibbundler — into
# $PREFIX, with no Homebrew involved. Two callers, both on GitHub's
# arm64 `macos-14` runner under Rosetta:
#   * _build-macos.yml's x86_64 lane, before it source-builds the
#     library chain and notcurses itself.
#   * _verify-macos-x86_64.yml, before its source-build pass builds the
#     same library chain and runs Build.rakumod's source-build fallback.
#
# Why not Homebrew: both lanes used to install an x86_64 Homebrew under
# /usr/local next to the runner's arm64 one and take these tools from
# it. Homebrew 7.0.0 (September 2026) moved Intel macOS to Tier 3, and
# its installer now refuses outright when run under `arch -x86_64` on
# Apple Silicon ("Homebrew on macOS is only supported on Apple Silicon
# processors!") — which is what broke the r16 binary release. GitHub's
# Intel macOS runners are not the way out either: the lanes ran on
# those before and were too flaky to release from. So the lanes stay
# on arm64 + Rosetta and get their tools from here instead.
#
# Why every tool needs an x86_64 slice: the x86_64 lanes dispatch every
# compile as `arch -x86_64 <tool>`, and arch(1) refuses an arm64-only
# binary outright ("Bad CPU type in executable") — which is exactly
# what the runner's own /opt/homebrew/bin/{cmake,ninja,pkg-config} are.
# Once a tool is running as x86_64, everything it spawns inherits the
# x86_64 preference, so a universal cc/ld emits x86_64 Mach-O without
# any -arch flag. That inheritance is also why Build.rakumod's own
# `cmake` call (no CMAKE_OSX_ARCHITECTURES) builds x86_64 when the
# verify lane runs it from an x86_64 Rakudo.
#
# Where each tool comes from:
#   * cmake + ninja — PyPI wheels, whose binaries are universal2
#     (x86_64 + arm64). meson — PyPI wheel, pure Python. All three go
#     into a venv made from Apple's own /usr/bin/python3 (the Xcode /
#     Command Line Tools Python 3.9, itself universal), pinned by
#     version AND by wheel SHA-256 (pip --require-hashes), so a
#     re-uploaded or substituted wheel fails the install instead of
#     running. The 3.9 interpreter caps two pins: pip 26.0.x and meson
#     1.11.x are the last releases that still support it (pip 26.1 and
#     meson 1.12 require 3.10). Neither cap costs anything here — the
#     only meson project we build is dav1d, which needs meson >= 0.49.
#   * pkgconf, nasm, dylibbundler — no wheels exist, so they are
#     compiled here from pinned upstream tarballs, and each tarball's
#     SHA-256 is checked before it is extracted. A fallback mirror is
#     tried when upstream is unreachable; the pinned hash is what makes
#     any mirror trustworthy, so a fallback can never change what we
#     build.
#
# pkgconf rather than freedesktop pkg-config 0.29.2: the arm64 lane's
# `pkg-config` already IS pkgconf (Homebrew's pkg-config formula is an
# alias for it) and so is the Windows lanes' MSYS2 one, so this keeps
# every lane on one implementation. pkg-config 0.29.2 is also the last
# release of a project unmaintained since 2017, and needs its bundled
# copy of glib 2.x (--with-internal-glib) to build without a system
# glib; pkgconf is small, self-contained C. Its compiled-in default
# search path is this prefix only, and every consumer passes
# PKG_CONFIG_PATH explicitly — so nothing else on the runner (arm64
# Homebrew's .pc files above all, which would hand an x86_64 link
# arm64 libraries) can leak into a lookup.
#
# Layout:
#   $PREFIX/bin   the ONE directory callers put on PATH: pkgconf plus a
#                 `pkg-config` symlink to it, nasm + ndisasm,
#                 dylibbundler, and symlinks to cmake/ctest/cpack/ninja's
#                 real Mach-O binaries and to the venv's meson. Linking
#                 the real cmake rather than PATH-ing the venv's
#                 bin/cmake (a Python console-script shim) keeps
#                 `lipo -archs "$(command -v cmake)"` meaningful and
#                 saves a Python start-up per cmake call; CMake resolves
#                 its CMAKE_ROOT through the symlink.
#   $PREFIX/venv  the Python venv.
#
# Usage:
#   PREFIX=<dir> arch -x86_64 bash build-macos-x86_64-tools.sh
#       Install, then assert. Idempotent: anything already present at
#       its pinned version is kept, so a restored actions/cache makes
#       this a few-second check. The venv is additionally rebuilt if
#       the interpreter it was made from has moved (a runner image
#       whose default Xcode changed under a restored cache).
#   PREFIX=<dir> bash build-macos-x86_64-tools.sh --check
#       Assert only, against the CURRENT PATH. Run it in a step after
#       $PREFIX/bin has gone into $GITHUB_PATH: it proves each tool
#       resolves to $PREFIX/bin rather than to /opt/homebrew, carries
#       an x86_64 slice, and actually runs under `arch -x86_64`.
set -euxo pipefail

MODE='install'
case "${1:-}" in
    '')       ;;
    --check)  MODE='check' ;;
    *)
        echo "❌ Unknown argument '$1'. Usage: $0 [--check]" >&2
        exit 1
        ;;
esac

PREFIX="${PREFIX:?PREFIX must be set to the toolchain install dir}"
VENV="$PREFIX/venv"
SYSTEM_PYTHON='/usr/bin/python3'

# --- Pins ------------------------------------------------------------
#
# PyPI wheels. Each SHA-256 is that of the single wheel file pip will
# pick on macOS (`py3-none-macosx_*_universal2` for cmake/ninja,
# `py3-none-any` for meson/pip) as listed under "digests" at
# https://pypi.org/pypi/<name>/<version>/json. When bumping, check the
# new version's Requires-Python still admits 3.9, and that cmake/ninja
# still ship a universal2 wheel.
PIP_VERSION='26.0.1'
PIP_SHA256='bdb1b08f4274833d62c1aa29e20907365a2ceb950410df15fc9521bad440122b'
# 4.4.x — the line the arm64 lane's Homebrew cmake is on. notcurses
# needs >= 3.21; every source-built dependency already configures under
# 4.x on the arm64 lane.
CMAKE_VERSION='4.4.3'
CMAKE_SHA256='6c95b37116bb5c714656e4f76931ebdcb739209a1aee91cf51408ccfe137694e'
NINJA_VERSION='1.13.2'
NINJA_SHA256='fd82e26c0706ad4ab88e5fdd26f3fab0a987a90f810160f6c322e752c6af298b'
MESON_VERSION='1.11.2'
MESON_SHA256='7e4f6e83fec83e3eaac928e058b073c7557b282c35b6a2024cea143a39926a39'

# Source tarballs. Upstream publishes no checksum files for any of
# these; the pinned hashes were taken from the downloaded files and
# cross-checked against Homebrew's formula for the same URL and
# Gentoo's distfiles mirror copy.
#
# pkgconf 3.0.7 still ships an autotools build in its release tarball;
# upstream plans to drop it in 3.1, so a bump past 3.0.x has to switch
# build_pkgconf to `meson setup` (meson is already in this toolchain).
PKGCONF_VERSION='3.0.7'
PKGCONF_SHA256='c926ff491cbd9a331a589160811bd97ab1749b4d5198a519338f2cdfabe6940a'
PKGCONF_URL="https://distfiles.ariadne.space/pkgconf/pkgconf-${PKGCONF_VERSION}.tar.xz"
NASM_VERSION='3.02'
NASM_SHA256='87336eba53b4acfe917424ab5d500d2b0054d9f5148d35c2273ccf2cfb712f0d'
NASM_URL="https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/nasm-${NASM_VERSION}.tar.xz"
# dylibbundler has no release tarballs, only tags; GitHub's tag archive
# is what Homebrew and MacPorts build from as well.
DYLIBBUNDLER_VERSION='1.0.5'
DYLIBBUNDLER_SHA256='13384ebe7ca841ec392ac49dc5e50b1470190466623fa0e5cd30f1c634858530'
DYLIBBUNDLER_URL="https://github.com/auriamg/macdylibbundler/archive/refs/tags/${DYLIBBUNDLER_VERSION}.tar.gz"

# Every tool callers resolve from $PREFIX/bin, in the order they are
# checked.
TOOLS='cmake ctest cpack ninja meson pkg-config pkgconf nasm dylibbundler'

# --- Assertions ------------------------------------------------------

fail() {
    echo "::error::$*" >&2
    echo "❌ $*" >&2
    exit 1
}

# The architectures lipo reports for a Mach-O file (following
# symlinks), or the empty string for anything lipo can't read.
archs_of() {
    lipo -archs "$1" 2>/dev/null || true
}

# assert_x86_64_slice <label> <path>
assert_x86_64_slice() {
    local archs
    archs=$(archs_of "$2")
    case " $archs " in
        *' x86_64 '*)
            echo "ok: $1 ($2) carries x86_64 [$archs]"
            ;;
        *)
            fail "$1 ($2) has no x86_64 slice (lipo -archs: '${archs:-<not a Mach-O file>}'). \
Under 'arch -x86_64' it would die with \"Bad CPU type in executable\"."
            ;;
    esac
}

# The binary whose CPU slices decide whether <tool> runs under
# `arch -x86_64`. meson is a Python script, so that is its interpreter,
# the venv's python3.
mach_o_of() {
    case "$1" in
        meson) echo "$VENV/bin/python3" ;;
        *)     echo "$2" ;;
    esac
}

# tool_version_ok <tool> <path> — 0 when <path> runs as x86_64 and
# reports the pinned version. Run through `arch -x86_64` on purpose:
# that is the exact invocation that fails on an arm64-only binary.
# Compared against the first line of output, whole, so 4.4.30 can't
# pass for 4.4.3.
tool_version_ok() {
    local tool=$1 path=$2 out
    [[ -x "$path" ]] || return 1
    case "$tool" in
        cmake|ctest|cpack)
            out=$(arch -x86_64 "$path" --version 2>&1) || return 1
            [[ "${out%%$'\n'*}" == "$tool version $CMAKE_VERSION" ]]
            ;;
        ninja)
            # PyPI's ninja is Kitware's jobserver-enabled build, which
            # reports e.g. "1.13.2.git.kitware.jobserver-pipe-1". The
            # "$NINJA_VERSION." prefix keeps 1.13.20 from matching 1.13.2.
            out=$(arch -x86_64 "$path" --version 2>&1) || return 1
            [[ "$out" == "$NINJA_VERSION" || "$out" == "$NINJA_VERSION".* ]]
            ;;
        meson)
            out=$(arch -x86_64 "$path" --version 2>&1) || return 1
            [[ "$out" == "$MESON_VERSION" ]]
            ;;
        pkg-config|pkgconf)
            out=$(arch -x86_64 "$path" --version 2>&1) || return 1
            [[ "$out" == "$PKGCONF_VERSION" ]]
            ;;
        nasm)
            out=$(arch -x86_64 "$path" -v 2>&1) || return 1
            [[ "$out" == "NASM version $NASM_VERSION "* ]]
            ;;
        dylibbundler)
            # No --version flag; -h prints "dylibbundler <version>"
            # first and exits 0.
            out=$(arch -x86_64 "$path" -h 2>&1) || return 1
            [[ "${out%%$'\n'*}" == "dylibbundler $DYLIBBUNDLER_VERSION" ]]
            ;;
        *)
            fail "tool_version_ok: no version probe for '$tool'"
            ;;
    esac
}

# assert_toolchain <prefix|path>
#   prefix — check $PREFIX/bin/<tool> directly (end of an install run,
#            independent of whatever PATH the caller has).
#   path   — check what `command -v <tool>` resolves to, and require
#            that to BE $PREFIX/bin/<tool> (the --check mode).
assert_toolchain() {
    local how=$1 tool path
    for tool in $TOOLS; do
        if [[ "$how" == 'path' ]]; then
            path=$(command -v "$tool" || true)
            if [[ "$path" != "$PREFIX/bin/$tool" ]]; then
                fail "'$tool' resolves to '${path:-<nothing>}' on PATH, not to \
$PREFIX/bin/$tool. $PREFIX/bin must come before /opt/homebrew/bin (arm64-only \
tools) on PATH."
            fi
        else
            path="$PREFIX/bin/$tool"
        fi
        assert_x86_64_slice "$tool" "$(mach_o_of "$tool" "$path")"
        tool_version_ok "$tool" "$path" \
            || fail "'$path' does not run as x86_64 at its pinned version."
        echo "ok: $tool runs under arch -x86_64 at its pinned version"
    done
    # The interpreter the venv was made from, by its own name — meson's
    # check above already covered it, but the spec of this toolchain is
    # "every binary in it is x86_64-capable", and this is one of them.
    assert_x86_64_slice 'venv python3' "$VENV/bin/python3"

    if [[ "$how" == 'path' ]]; then
        # Not ours, but the workflows `arch -x86_64` both of these
        # directly (`host-arch bash scripts/ci/...`, `host-arch cc`), so
        # PATH resolving either to an arm64-only build — a Homebrew bash
        # landing on a future runner image, say — fails the same way.
        # Apple's /bin/bash and /usr/bin/cc are universal.
        for tool in bash cc; do
            path=$(command -v "$tool" || true)
            [[ -n "$path" ]] || fail "'$tool' is not on PATH."
            assert_x86_64_slice "$tool" "$path"
        done
    fi
}

if [[ "$MODE" == 'check' ]]; then
    assert_toolchain path
    echo "✅ x86_64 toolchain resolves from $PREFIX/bin and runs under Rosetta."
    exit 0
fi

# --- Install ---------------------------------------------------------

if [[ "$(uname -s)" != 'Darwin' || "$(uname -m)" != 'x86_64' ]]; then
    fail "must run as x86_64 macOS (got $(uname -s)/$(uname -m)). \
Invoke it as: arch -x86_64 bash $0"
fi

mkdir -p "$PREFIX/bin"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

# Pinned here rather than inherited: the build lane runs this with
# MACOSX_DEPLOYMENT_TARGET=10.15 in its env and the verify lane with
# none, but both share one cache key, so what lands in $PREFIX must not
# depend on which of them built it. Nothing here ships; 10.15 is simply
# the x86_64 floor.
export MACOSX_DEPLOYMENT_TARGET='10.15'

WORK="$(mktemp -d "${TMPDIR:-/tmp}/macos-x86_64-tools.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# pip, hermetically: no user/site config, no prompts, no self-update
# nag, and no HTTP/wheel cache under ~/Library/Caches — actions/cache
# already keeps the installed result, so a pip cache would only be a
# second, unkeyed copy written outside $PREFIX.
export PIP_CONFIG_FILE=/dev/null
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_NO_INPUT=1
export PIP_NO_CACHE_DIR=1

# fetch_verified <dest> <sha256> <url> [<fallback-url>...]
fetch_verified() {
    local dest=$1 sha=$2 url got
    shift 2
    for url in "$@"; do
        if ! curl -fSL --retry 5 --retry-delay 10 -o "$dest" "$url"; then
            echo "::warning::download failed: $url" >&2
            continue
        fi
        got=$(shasum -a 256 "$dest" | awk '{print $1}')
        if [[ "$got" == "$sha" ]]; then
            echo "ok: $(basename "$dest") SHA-256 $got"
            return 0
        fi
        echo "::warning::SHA-256 mismatch for $url: got $got, pinned $sha" >&2
        rm -f "$dest"
    done
    fail "no source for $(basename "$dest") matched pinned SHA-256 $sha (tried: $*)."
}

# Gentoo's distfiles mirror keeps byte-identical copies of upstream
# release tarballs, filed under the first two hex digits of the
# BLAKE2b of the file name.
gentoo_mirror_url() {
    local dir
    dir=$("$SYSTEM_PYTHON" -c \
        'import hashlib, sys; print(hashlib.blake2b(sys.argv[1].encode()).hexdigest()[:2])' \
        "$1")
    echo "https://distfiles.gentoo.org/distfiles/$dir/$1"
}

# 0 when the venv works, was made from the interpreter /usr/bin/python3
# resolves to today, still lives at the path it was made at, and holds
# exactly the pinned packages.
venv_ok() {
    local want got shebang
    [[ -x "$VENV/bin/python3" ]] || return 1
    want=$("$SYSTEM_PYTHON" -c 'import sys; print(sys.base_prefix)')
    got=$("$VENV/bin/python3" -c 'import sys; print(sys.base_prefix)' 2>/dev/null) \
        || return 1
    [[ "$got" == "$want" ]] || return 1
    # A venv is not relocatable: its console scripts name their
    # interpreter by absolute path. A cache restored under a different
    # workspace path would still pass the checks above while meson's
    # shebang pointed at a directory that no longer exists.
    [[ -f "$VENV/bin/meson" ]] || return 1
    IFS= read -r shebang < "$VENV/bin/meson" || return 1
    [[ "$shebang" == "#!$VENV/bin/python3" ]] || return 1
    "$VENV/bin/python3" - "$PIP_VERSION" "$CMAKE_VERSION" "$NINJA_VERSION" "$MESON_VERSION" <<'EOF'
import sys
import importlib.metadata as md
want = dict(zip(("pip", "cmake", "ninja", "meson"), sys.argv[1:]))
try:
    sys.exit(0 if all(md.version(n) == v for n, v in want.items()) else 1)
except md.PackageNotFoundError:
    sys.exit(1)
EOF
}

build_venv() {
    if venv_ok; then
        echo "ok: venv at $VENV already holds the pinned Python tools"
        return 0
    fi
    rm -rf "$VENV"
    "$SYSTEM_PYTHON" -c 'import venv' \
        || fail "$SYSTEM_PYTHON cannot import venv — are the Xcode command line tools installed?"
    # This script runs as x86_64, so the interpreter — and through it
    # the venv's — runs its x86_64 slice.
    "$SYSTEM_PYTHON" -m venv "$VENV"

    printf 'pip==%s --hash=sha256:%s\n' "$PIP_VERSION" "$PIP_SHA256" \
        > "$WORK/requirements-pip.txt"
    {
        printf 'cmake==%s --hash=sha256:%s\n' "$CMAKE_VERSION" "$CMAKE_SHA256"
        printf 'ninja==%s --hash=sha256:%s\n' "$NINJA_VERSION" "$NINJA_SHA256"
        printf 'meson==%s --hash=sha256:%s\n' "$MESON_VERSION" "$MESON_SHA256"
    } > "$WORK/requirements-tools.txt"

    # --only-binary: wheels only, never an sdist build. --no-deps: none
    # of the four has a runtime dependency on Python 3.9, and with it
    # nothing outside the pinned, hashed set can ever be pulled in.
    local req
    for req in requirements-pip.txt requirements-tools.txt; do
        "$VENV/bin/python3" -m pip install \
            --require-hashes --only-binary=:all: --no-deps \
            -r "$WORK/$req"
    done
    venv_ok || fail "venv at $VENV does not hold the pinned versions after install."
}

link_python_tools() {
    local cmake_bin_dir ninja_bin_dir tool
    cmake_bin_dir=$("$VENV/bin/python3" -c 'import cmake; print(cmake.CMAKE_BIN_DIR)')
    ninja_bin_dir=$("$VENV/bin/python3" -c 'import ninja; print(ninja.BIN_DIR)')
    for tool in cmake ctest cpack; do
        ln -sfn "$cmake_bin_dir/$tool" "$PREFIX/bin/$tool"
    done
    ln -sfn "$ninja_bin_dir/ninja" "$PREFIX/bin/ninja"
    ln -sfn "$VENV/bin/meson" "$PREFIX/bin/meson"
}

build_pkgconf() {
    if tool_version_ok pkgconf "$PREFIX/bin/pkgconf" \
       && tool_version_ok pkg-config "$PREFIX/bin/pkg-config"; then
        echo "ok: pkgconf $PKGCONF_VERSION already installed"
        return 0
    fi
    local tarball="pkgconf-${PKGCONF_VERSION}.tar.xz"
    fetch_verified "$WORK/$tarball" "$PKGCONF_SHA256" \
        "$PKGCONF_URL" "$(gentoo_mirror_url "$tarball")"
    tar -xf "$WORK/$tarball" -C "$WORK"
    # Static libpkgconf: the binary then carries no dylib reference into
    # this prefix. System dirs are the classic pkg-config ones (-I and
    # -L for them are filtered from output, as the arm64 lane's
    # Homebrew pkgconf does); the default .pc search path is left at
    # this prefix's own lib/ and share/pkgconfig — see the header.
    (
        cd "$WORK/pkgconf-${PKGCONF_VERSION}"
        ./configure \
            --prefix="$PREFIX" \
            --disable-shared \
            --enable-static \
            --disable-dependency-tracking \
            --with-system-libdir=/usr/lib \
            --with-system-includedir=/usr/include
        make -j"$JOBS"
        make install
    )
    ln -sfn pkgconf "$PREFIX/bin/pkg-config"
}

build_nasm() {
    if tool_version_ok nasm "$PREFIX/bin/nasm"; then
        echo "ok: nasm $NASM_VERSION already installed"
        return 0
    fi
    local tarball="nasm-${NASM_VERSION}.tar.xz"
    fetch_verified "$WORK/$tarball" "$NASM_SHA256" \
        "$NASM_URL" "$(gentoo_mirror_url "$tarball")"
    tar -xf "$WORK/$tarball" -C "$WORK"
    (
        cd "$WORK/nasm-${NASM_VERSION}"
        ./configure --prefix="$PREFIX"
        make -j"$JOBS"
        make install
    )
}

build_dylibbundler() {
    if tool_version_ok dylibbundler "$PREFIX/bin/dylibbundler"; then
        echo "ok: dylibbundler $DYLIBBUNDLER_VERSION already installed"
        return 0
    fi
    local tarball="macdylibbundler-${DYLIBBUNDLER_VERSION}.tar.gz"
    fetch_verified "$WORK/$tarball" "$DYLIBBUNDLER_SHA256" "$DYLIBBUNDLER_URL"
    tar -xf "$WORK/$tarball" -C "$WORK"
    (
        cd "$WORK/macdylibbundler-${DYLIBBUNDLER_VERSION}"
        make -j"$JOBS"
        make install PREFIX="$PREFIX"
    )
}

build_venv
link_python_tools
build_pkgconf
build_nasm
build_dylibbundler

assert_toolchain prefix
echo "✅ x86_64 toolchain installed under $PREFIX/bin."
