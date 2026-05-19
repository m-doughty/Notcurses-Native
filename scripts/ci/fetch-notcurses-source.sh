#!/usr/bin/env bash
# Fetch the notcurses source tree pinned by NOTCURSES_FORK at the
# dist root. Mirrors Build.rakumod's !ensure-notcurses-source logic
# so install-time (Build.rakumod) and release-time (CI) build from
# the exact same SHA — no more "vendor/notcurses and NOTCURSES_FORK
# drift" class of bug.
#
# Behaviour:
#   1. Parse NOTCURSES_FORK for `url=` + `sha=` (40-char lowercase
#      hex). Refuses malformed input.
#   2. Cache the checkout under $NOTCURSES_SRC_CACHE/<sha>/. Default
#      cache root is workspace-relative ($PWD/_ci-cache/notcurses-source)
#      so GHA's actions/cache can persist it across runs without
#      needing access to $HOME. Override via $NOTCURSES_SRC_CACHE.
#   3. If the cache dir already has CMakeLists.txt and `git
#      rev-parse HEAD` matches the pinned SHA, reuse it. Otherwise
#      wipe + `git init` + `fetch --depth 1 origin <sha>` +
#      `checkout FETCH_HEAD`.
#   4. Emit the resolved path on stdout (always). When $GITHUB_ENV
#      is set (i.e. running inside a GHA step), also append
#      `NOTCURSES_SRC_DIR=<path>` so subsequent steps see it.
#
# Escape hatch: $NOTCURSES_NATIVE_VENDOR_DIR=<path> short-circuits
# everything and uses that local checkout verbatim. Matches
# Build.rakumod's behaviour — useful for fork iteration without
# push cycles, and the only way to build in an airgapped env.

set -euo pipefail

# Resolve the repo root. We assume this script lives under
# `<root>/scripts/ci/` and the dist root holds NOTCURSES_FORK.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$script_dir/../.." && pwd)"

# Local-vendor escape hatch — matches Build.rakumod.
if [[ -n "${NOTCURSES_NATIVE_VENDOR_DIR:-}" ]]; then
  if [[ ! -f "$NOTCURSES_NATIVE_VENDOR_DIR/CMakeLists.txt" ]]; then
    echo "❌ NOTCURSES_NATIVE_VENDOR_DIR=$NOTCURSES_NATIVE_VENDOR_DIR is not a" >&2
    echo "   notcurses source tree (no CMakeLists.txt)." >&2
    exit 1
  fi
  echo "Using NOTCURSES_NATIVE_VENDOR_DIR=$NOTCURSES_NATIVE_VENDOR_DIR as source tree." >&2
  echo "$NOTCURSES_NATIVE_VENDOR_DIR"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "NOTCURSES_SRC_DIR=$NOTCURSES_NATIVE_VENDOR_DIR" >> "$GITHUB_ENV"
  fi
  exit 0
fi

pin_file="$root/NOTCURSES_FORK"
if [[ ! -f "$pin_file" ]]; then
  echo "❌ Missing NOTCURSES_FORK at $pin_file." >&2
  exit 1
fi

url=""
sha=""
while IFS= read -r line || [[ -n "$line" ]]; do
  # Strip trailing CR — git on Windows may check out NOTCURSES_FORK
  # with CRLF line endings, and `read -r` leaves the \r intact, which
  # pushes the SHA past 40 chars and trips the hex regex below.
  # The `|| [[ -n "$line" ]]` keeps the last line if it's missing a
  # trailing newline.
  line="${line%$'\r'}"
  # Skip comments and blank lines (matches Build.rakumod's parser).
  case "$line" in
    \#*|'') continue ;;
    url=*)  url="${line#url=}" ;;
    sha=*)  sha="${line#sha=}" ;;
    *)
      echo "❌ Malformed line in NOTCURSES_FORK: '$line'." >&2
      echo "   Expected '# comment', 'url=…', or 'sha=…'." >&2
      exit 1
      ;;
  esac
done < "$pin_file"

[[ -n "$url" ]] || { echo "❌ NOTCURSES_FORK missing required key url=." >&2; exit 1; }
[[ -n "$sha" ]] || { echo "❌ NOTCURSES_FORK missing required key sha=." >&2; exit 1; }

# 40-char lowercase hex — refuse short SHAs or branch names so a
# moving target can never silently change what we build.
if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "❌ NOTCURSES_FORK sha=$sha must be a 40-char lowercase hex string." >&2
  exit 1
fi

cache_root="${NOTCURSES_SRC_CACHE:-$root/_ci-cache/notcurses-source}"
src_dir="$cache_root/$sha"

# Reuse the cache when the on-disk tree's HEAD matches the pin —
# defends against an aborted earlier fetch that left a partial tree.
if [[ -f "$src_dir/CMakeLists.txt" ]] \
   && head=$(git -C "$src_dir" rev-parse HEAD 2>/dev/null) \
   && [[ "$head" == "$sha" ]]; then
  echo "Reusing cached notcurses source at $src_dir." >&2
  echo "$src_dir"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "NOTCURSES_SRC_DIR=$src_dir" >> "$GITHUB_ENV"
  fi
  exit 0
fi

# Stale or absent — wipe and re-fetch.
rm -rf "$src_dir"
mkdir -p "$src_dir"

echo "Fetching notcurses source from $url @ $sha..." >&2
git init --quiet "$src_dir"
git -C "$src_dir" remote add origin "$url"
# protocol.version=2 + fetch-by-SHA: GitHub allows fetching arbitrary
# reachable commits via this combination. Without v2 the server can
# refuse non-branch refs.
git -C "$src_dir" -c protocol.version=2 fetch --depth 1 --quiet origin "$sha"
git -C "$src_dir" checkout --quiet FETCH_HEAD

# Belt-and-braces: verify HEAD really is the SHA we asked for.
head=$(git -C "$src_dir" rev-parse HEAD)
if [[ "$head" != "$sha" ]]; then
  echo "❌ Fetched HEAD ($head) doesn't match pinned SHA ($sha)." >&2
  rm -rf "$src_dir"
  exit 1
fi

echo "Fetched notcurses source to $src_dir." >&2
echo "$src_dir"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "NOTCURSES_SRC_DIR=$src_dir" >> "$GITHUB_ENV"
fi
