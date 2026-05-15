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
# in their own directory at load time.
find bundle -name '*.so*' -type f | while read f; do
  patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
done

find bundle -name '*.so*' -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true

echo "--- bundle contents ---"
ls -la bundle/
echo "--- ldd libnotcurses.so ---"
ldd bundle/libnotcurses.so || true
