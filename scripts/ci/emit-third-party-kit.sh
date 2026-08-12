#!/usr/bin/env bash
# Write the licensing kit into a pack: THIRD-PARTY.md at the pack
# root plus a LICENSES/ directory holding the full text of every
# licence that pack's contents are under.
#
#   usage: emit-third-party-kit.sh <macos|linux|windows> [bundle-dir]
#
# Both are generated from resources/third-party.json so the document
# and the gate can never disagree — scripts/ci/audit-third-party.sh
# reads the same file, and it runs immediately after this script does,
# over the pack this script has just added files to.
#
# Why this ships INSIDE the archive rather than only living in the
# repository: the archive is what a user actually receives. The
# permissive licences in it (BSD-2, BSD-3, MIT, X11, Zlib) all require
# their copyright notice and licence text to accompany a binary
# redistribution, and the copyleft ones (FFmpeg's LGPL-2.1,
# libunistring's LGPL-3.0) require the recipient be told of their
# rights and where the source is. A file in a git repository the user
# has never visited discharges none of that; a file next to the .so
# they just downloaded does.
#
# PORTABILITY: runs under GitHub's macOS images, where `shell: bash`
# is /bin/bash 3.2. No `mapfile`, no `declare -A`, and array
# expansions are guarded for `set -u`. Needs jq (see the note in
# audit-third-party.sh).
set -euo pipefail

PLATFORM="${1:-}"
BUNDLE_DIR="${2:-bundle}"

case "$PLATFORM" in
    macos|linux|windows) ;;
    *)
        echo "usage: $0 <macos|linux|windows> [bundle-dir]" >&2
        echo "  (got '${PLATFORM:-<nothing>}')" >&2
        exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="${THIRD_PARTY_MANIFEST:-$REPO_ROOT/resources/third-party.json}"
LICENSE_DIR="${THIRD_PARTY_LICENSE_DIR:-$REPO_ROOT/resources/licenses}"

if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is not on PATH — cannot read the manifest." >&2
    exit 1
fi
for path in "$MANIFEST" "$LICENSE_DIR"; do
    if [[ ! -e "$path" ]]; then
        echo "❌ '$path' not found." >&2
        exit 1
    fi
done
if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "❌ Bundle directory '$BUNDLE_DIR' does not exist." >&2
    exit 1
fi

# Components that can appear in THIS pack: a non-empty pattern list
# for this platform. Everything else is someone else's platform and
# would only be noise in a document meant to describe what the reader
# is holding.
present_ids=()
while IFS= read -r id; do
    [[ -n "$id" ]] && present_ids+=( "$id" )
done < <(
    jq -r --arg p "$PLATFORM" '
        .components[]
        | select(((.binaries[$p].patterns // []) | length) > 0)
        | .id
    ' "$MANIFEST"
)

if (( ${#present_ids[@]} == 0 )); then
    echo "❌ No component in the manifest ships on '$PLATFORM' — that cannot be right." >&2
    exit 1
fi

# ---------------------------------------------------------------- #
# LICENSES/
# ---------------------------------------------------------------- #
# Every licence text referenced by a component that can appear here.
# Note this is "can appear", not "did appear": the two Windows
# compiler runtimes are mutually exclusive per subsystem and several
# components are optional, but the set of texts a pack carries should
# be a property of the platform, not of which DLLs the linker happened
# to pull in on the day. A licence text nobody needed is inert; a
# missing one is a notice we failed to give.
license_out="$BUNDLE_DIR/LICENSES"
rm -rf "$license_out"
mkdir -p "$license_out"

copied=0
while IFS= read -r lic; do
    [[ -n "$lic" ]] || continue
    if [[ ! -f "$LICENSE_DIR/$lic" ]]; then
        echo "❌ Manifest references licence text '$lic', which is not in $LICENSE_DIR." >&2
        exit 1
    fi
    cp "$LICENSE_DIR/$lic" "$license_out/$lic"
    copied=$(( copied + 1 ))
done < <(
    jq -r --arg p "$PLATFORM" '
        [ .components[]
          | select(((.binaries[$p].patterns // []) | length) > 0)
          | ."license-files"[] ]
        | unique | .[]
    ' "$MANIFEST"
)
echo "Wrote $copied licence text(s) to $license_out/"

# ---------------------------------------------------------------- #
# THIRD-PARTY.md
# ---------------------------------------------------------------- #
md="$BUNDLE_DIR/THIRD-PARTY.md"

{
    printf '# Third-party components in this package\n\n'
    printf 'Platform: %s\n\n' "\`$PLATFORM\`"
    cat <<'PREAMBLE'
This archive is a binary redistribution. Everything it contains is
listed below with the licence it is conveyed under and the exact
source it was built from. Full licence texts are in `LICENSES/`
alongside this file.

Where the source is given as a tarball URL with a SHA-256, that exact
tarball is attached to the GitHub release this archive came from, so
the corresponding source for these binaries stays available for as
long as the binaries do. That is a requirement of the LGPL for FFmpeg
and GNU libunistring; the other tarballs are attached for consistency,
so that "which source built this?" has one answer for every component
rather than two kinds of answer.

FFmpeg here is a decoder-only build with neither `--enable-gpl` nor
`--enable-nonfree`, so it is conveyed under the LGPL v2.1 or later and
none of FFmpeg's GPL-only components are compiled in.

PREAMBLE
    printf '## Summary\n\n'
    printf '| Component | Version | Licence (SPDX) | Source |\n'
    printf '|---|---|---|---|\n'
    jq -r --arg p "$PLATFORM" '
        .components[]
        | select(((.binaries[$p].patterns // []) | length) > 0)
        | . as $c
        | ( if   $c.source.kind == "tarball"         then "[tarball](\($c.source.url))"
            elif $c.source.kind == "git"             then "[git](\($c.source.url)) @ `\($c.source.ref)`"
            elif $c.source.kind == "in-tree"         then "[this project](\($c.source.url))"
            else "platform package manager"
            end ) as $src
        | "| \($c.name) | \($c.version) | `\($c["spdx-license"])` | \($src) |"
    ' "$MANIFEST"
    printf '\n## Details\n'
    jq -r --arg p "$PLATFORM" '
        .components[]
        | select(((.binaries[$p].patterns // []) | length) > 0)
        | . as $c
        | [ "",
            "### \($c.name) — \($c.version)",
            "",
            "* Licence: `\($c["spdx-license"])`"
              + (if $c["conveyed-under"] then " — conveyed under `\($c["conveyed-under"])`" else "" end),
            "* Licence text: " + ([ $c["license-files"][] | "`LICENSES/\(.)`" ] | join(", ")),
            "* \($c.copyright)",
            "* Upstream: <\($c["project-url"])>"
          ]
          + ( if $c.source.kind == "tarball" then
                [ "* Source: <\($c.source.url)>",
                  "* Source SHA-256: `\($c.source.sha256)`",
                  "* Attached to this release as `\($c.source.filename)`" ]
              elif $c.source.kind == "git" then
                [ "* Source: <\($c.source.url)> at commit `\($c.source.ref)`" ]
              elif $c.source.kind == "in-tree" then
                [ "* Source: <\($c.source.url)>" ]
              else
                [ "* Source: supplied by the package manager of the build platform" ]
              end )
          + [ "* Files in this archive: " + ([ $c.binaries[$p].patterns[] | "`\(.)`" ] | join(", ")) ]
          + ( if $c.notes then [ "", $c.notes ] else [] end )
        | .[]
    ' "$MANIFEST"
    cat <<'FOOTER'

---

Generated from `resources/third-party.json` by
`scripts/ci/emit-third-party-kit.sh`. Do not edit this file by hand — edit
the manifest, which `scripts/ci/audit-third-party.sh` enforces against the
actual contents of this archive on every release.
FOOTER
} > "$md"

echo "Wrote $md ($(wc -l < "$md" | tr -d ' ') lines) for ${#present_ids[@]} component(s)"
