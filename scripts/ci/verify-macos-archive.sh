#!/usr/bin/env bash
set -euo pipefail

arch=${1:?expected arm64 or x86_64}
archive=${2:?expected tar.gz archive}
case "$arch" in
    arm64|x86_64) ;;
    *) echo "Unknown architecture: $arch" >&2; exit 1 ;;
esac

script_dir=$(cd "$(dirname "$0")" && pwd -P)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/notcurses-load.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
scratch=$(cd "$scratch" && pwd -P)
mkdir "$scratch/bundle" "$scratch/empty"
tar -xzf "$archive" -C "$scratch/bundle"

for file in "$scratch/bundle/"*.dylib; do
    [[ -L "$file" ]] && continue
    actual=$(lipo -archs "$file")
    if [[ "$actual" != "$arch" ]]; then
        echo "::error file=$file::expected $arch, found $actual" >&2
        exit 1
    fi
done
bash "$script_dir/check-macos-load-commands.sh" --verify "$scratch/bundle"

cc -arch "$arch" -Wall -Wextra -Werror -o "$scratch/probe" "$script_dir/macos-load-probe.c"
# The thin probe runs in the target architecture (under Rosetta for
# x86_64 on arm64). Clear caller overrides and replace fallback paths.
cd "$scratch/empty"
env -i HOME="$scratch/empty"     DYLD_FALLBACK_LIBRARY_PATH="$scratch/empty"     DYLD_FALLBACK_FRAMEWORK_PATH="$scratch/empty"     "$scratch/probe" "$scratch/bundle"
