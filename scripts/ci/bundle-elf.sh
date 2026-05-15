#!/usr/bin/env bash
# Stage notcurses .so libs into bundle/, recursively walk ldd to copy
# ffmpeg sibling shared libs into the same directory, set DT_RUNPATH
# to $ORIGIN on every shipped .so so they find each other at load
# time, and strip.
#
# Honours $EXTRA_SKIP_LIBS (space-separated glob patterns) — alpine
# musl callers pass 'ld-musl-*.so.1 libc.musl-*.so.1' so we don't
# bundle musl's loader / libc (alpine systems already have them;
# bundling would produce a 2-libc conflict).
#
# Designed to run INSIDE a build container (manylinux2014 for glibc,
# alpine:3.20 for musl) — needs ldd, patchelf, strip on PATH. The
# extra LD_LIBRARY_PATH the caller may have exported (to point at
# workspace-cached ffmpeg) is preserved through to ldd via the env.

set -euxo pipefail

mkdir -p bundle
cd vendor/notcurses/build

for lib in libnotcurses libnotcurses-core libnotcurses-ffi; do
  found=$(find . -name "${lib}.so.*" -type f | sort | tail -1)
  [[ -z "$found" ]] && found=$(find . -name "${lib}.so" -type f | head -1)
  cp "$found" "../../../bundle/${lib}.so"
done

cd ../../..

# Skiplist: stay-dynamic system libraries. Bundling these would
# produce crt clashes / loader conflicts.
is_system_lib() {
  local name="$1"
  case "$name" in
    libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*| \
    librt.so.*|libstdc++.so.*|ld-linux*|libgcc_s.so.*| \
    libresolv.so.*|libnsl.so.*|linux-vdso.so.*| \
    libutil.so.*|libcrypt.so.*)
      return 0 ;;
  esac
  # Caller-supplied extra patterns (alpine musl loader names, etc.).
  if [[ -n "${EXTRA_SKIP_LIBS:-}" ]]; then
    local pat
    for pat in $EXTRA_SKIP_LIBS; do
      # shellcheck disable=SC2053
      [[ "$name" == $pat ]] && return 0
    done
  fi
  return 1
}

process_deps() {
  local lib="$1"
  # Strip any `(...)` trailing marker from ldd output and skip
  # non-absolute paths (catches `not found`, bare filenames, etc.).
  ldd "$lib" 2>/dev/null \
    | sed -n 's/ (.*)$//; s/^[[:space:]]*\([^ ]\+\) => \(.\+\)$/\1\t\2/p' \
    | while IFS=$'\t' read -r name path; do
        is_system_lib "$name" && continue
        [[ -z "$path" ]] && continue
        [[ "$path" != /* && "$path" != ?:[/\\]* ]] && continue
        if [[ ! -f "bundle/$name" ]]; then
          cp "$path" "bundle/$name"
          echo "Bundled: $name  (from $path)"
          process_deps "bundle/$name"  # recurse
        fi
      done
}

for lib in bundle/libnotcurses.so bundle/libnotcurses-core.so bundle/libnotcurses-ffi.so; do
  process_deps "$lib"
done

# Set rpath to $ORIGIN on every shipped .so so they find siblings
# in their own directory at load time. NO `|| true` here — silent
# patchelf failures would leave dylibs falling back to system paths
# at user-runtime; we fail loud instead.
find bundle -name '*.so*' -type f | while read f; do
  patchelf --set-rpath '$ORIGIN' "$f"
done

find bundle -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

# Hard audit: every non-symlink .so in bundle/ must now report
# RUNPATH=$ORIGIN. patchelf above can't set it if a binary has no
# PT_DYNAMIC, or already has DT_RPATH instead of DT_RUNPATH, or
# similar quirk — and the per-file failures get masked by the
# pipeline. Verify and fail loudly here.
echo "--- RUNPATH audit ---"
fail=0
for f in $(find bundle -name '*.so*' -type f ! -type l); do
    rpath=$(patchelf --print-rpath "$f" 2>/dev/null)
    if [[ "$rpath" != '$ORIGIN' ]]; then
        echo "::error file=$f::RUNPATH is '$rpath', expected '\$ORIGIN'"
        fail=1
    else
        echo "ok: $f RUNPATH=\$ORIGIN"
    fi
done
if (( fail != 0 )); then
    echo "❌ One or more bundled .so files don't have RUNPATH=\$ORIGIN."
    echo "   They'll fall back to /lib64/ etc. at user-runtime instead"
    echo "   of finding bundle siblings. Investigate the patchelf step."
    exit 1
fi

echo "--- bundle contents ---"
ls -la bundle/

# Diagnostic ldd in CLEAN env: the build set LD_LIBRARY_PATH +
# CMAKE_PREFIX_PATH etc. pointing at $CACHE/lib so cmake/configure
# could find source-built deps. Those env vars are still set when
# bundle-elf.sh runs, so a plain `ldd bundle/libnotcurses.so` would
# resolve via LD_LIBRARY_PATH instead of the binary's $ORIGIN
# RUNPATH, painting a misleading picture (deps showing as resolving
# to $CACHE/lib that won't exist on user machines). `env -i` wipes
# all env vars except PATH, mimicking the user-runtime ld.so view.
echo "--- ldd in clean env (user-runtime view) ---"
LDD_OUT=$(env -i PATH=/usr/bin:/bin ldd bundle/libnotcurses.so 2>&1 || true)
echo "$LDD_OUT"

# Hard audit: every "lib.so.N => path" line must have its path
# inside bundle/ UNLESS the lib is a system library we deliberately
# don't bundle (libc, libm, libpthread, libdl, librt, libgcc_s,
# linux-vdso, libstdc++, libresolv, libnsl, libutil, libcrypt,
# libcrypto for Linux; ld-linux* / ld-musl* loaders).
echo "--- non-system dep resolution audit ---"
fail=0
while IFS= read -r line; do
    # Skip lines that aren't "X => Y" form (linux-vdso prints just
    # "linux-vdso.so.1 (0x...)" without an arrow — those are system).
    if ! [[ "$line" =~ \=\> ]]; then
        continue
    fi
    # "    libfoo.so.N => /some/path (0x...)" — strip leading
    # whitespace, split on ' => '.
    libname="${line#"${line%%[![:space:]]*}"}"  # ltrim
    libname="${libname%% =>*}"
    rest="${line#*=> }"
    libpath="${rest% \(*}"
    case "$libname" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|\
        librt.so.*|libstdc++.so.*|libgcc_s.so.*|libresolv.so.*|\
        libnsl.so.*|libutil.so.*|libcrypt.so.*|libcrypto.so.*|\
        libssl.so.*|ld-linux*|ld-musl*|linux-vdso.so.*)
            continue ;;
    esac
    case "$libpath" in
        not\ found)
            echo "::error::Non-system lib '$libname' is NOT FOUND in clean env"
            fail=1 ;;
        bundle/*|*/bundle/*)
            # Inside bundle/ — matches both relative (`bundle/foo`,
            # which is what ldd emits when ld.so resolves via
            # $ORIGIN from the binary's own dir) and absolute
            # (`/work/bundle/foo`) forms.
            : ;;
        *)
            echo "::error::Non-system lib '$libname' resolves to '$libpath' (outside bundle/)"
            fail=1 ;;
    esac
done <<< "$LDD_OUT"
if (( fail != 0 )); then
    echo "❌ Bundle audit failed: one or more non-system deps don't"
    echo "   resolve to bundle/ at user-runtime. The shipped tarball"
    echo "   would fall back to system paths (different libs / missing"
    echo "   libs) on the user's machine."
    exit 1
fi
echo "✅ Bundle audit passed: every non-system dep resolves inside bundle/"
