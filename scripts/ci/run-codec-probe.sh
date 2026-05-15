#!/usr/bin/env bash
# Compile + run scripts/ci/codec-probe.c against the just-built
# bundle/ directory. Exits non-zero if the bundle's libavcodec is
# missing any required accelerated decoder (libdav1d, libvpx_vp8,
# libvpx_vp9, libopus) — blocks artefact upload at the build job
# level, so release.yml's `needs:` chain refuses to publish a
# bundle that would silently regress codec perf for users.
#
# Cross-platform: detects OS via uname to pick the right linker
# flags + library-search env var. Compiles with the host's `cc`
# (manylinux ships gcc-toolset, alpine ships gcc, macOS ships clang,
# msys2 ships gcc).
#
# Working directory: caller is expected to have bundle/ as a
# subdirectory of $PWD (the standard layout from build-linux-*.sh
# / bundle-macos action / bundle-dll action).
set -euxo pipefail

# LDFLAGS as a string (not array) so the empty-on-non-Linux case
# survives `set -u` on bash 3.x (macOS default) — bash 3.x treats
# "${arr[@]}" expansion of an empty array as unbound and exits.
# Unquoted "$LDFLAGS" with an empty string disappears via word
# splitting, which is what we want.
case "$(uname -s)" in
    Linux)
        LDFLAGS='-ldl'
        LIBPATH_VAR='LD_LIBRARY_PATH'
        PROBE_BIN='/tmp/codec-probe'
        ;;
    Darwin)
        LDFLAGS=''
        LIBPATH_VAR='DYLD_LIBRARY_PATH'
        PROBE_BIN='/tmp/codec-probe'
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LDFLAGS=''
        LIBPATH_VAR='PATH'
        PROBE_BIN='/tmp/codec-probe.exe'
        ;;
    *)
        echo "❌ Unknown OS '$(uname -s)' — extend run-codec-probe.sh" >&2
        exit 1
        ;;
esac

# Compile the probe. -O0 because we're not testing performance and
# the probe should compile fast (it's a few-line program).
# Intentional unquoted $LDFLAGS — empty string vanishes via word
# splitting on platforms without -ldl.
# shellcheck disable=SC2086
cc -O0 -o "$PROBE_BIN" scripts/ci/codec-probe.c $LDFLAGS

# Verify bundle/ has libavcodec before invoking the probe — better
# error than the probe's own "couldn't load" if we have an obviously
# missing bundle.
if ! ls bundle/libavcodec.* >/dev/null 2>&1 && \
   ! ls bundle/avcodec*.dll >/dev/null 2>&1; then
    echo "❌ bundle/ doesn't contain libavcodec — nothing to probe." >&2
    echo "   Probe expects to run AFTER bundling completes." >&2
    exit 1
fi

# Capture workspace root BEFORE we cd into bundle/, so the probe
# can resolve fixture paths like
# `$WORKSPACE_DIR/vendor/notcurses/data/chunli44.png` for its
# decode tests.
export WORKSPACE_DIR="$PWD"

# Run the probe with bundle/ as CWD and library-search env pointing
# at "." — combined this makes dlopen resolve libavcodec from the
# bundle, NOT from any host-installed libavcodec (which could mask
# the bundled one and produce a false-green probe against the
# wrong library). On Windows, cd'ing into bundle/ also gets bundled
# DLLs onto LoadLibrary's CWD search path.
cd bundle
case "$LIBPATH_VAR" in
    LD_LIBRARY_PATH)   LD_LIBRARY_PATH=".:${LD_LIBRARY_PATH:-}"     "$PROBE_BIN" ;;
    DYLD_LIBRARY_PATH) DYLD_LIBRARY_PATH=".:${DYLD_LIBRARY_PATH:-}" "$PROBE_BIN" ;;
    PATH)              PATH=".:$PATH"                                "$PROBE_BIN" ;;
esac
