#!/usr/bin/env bash
# Write the licensing kit into a pack: THIRD-PARTY.md at the pack
# root, a LICENSES/ directory holding the full text of every licence
# that pack's contents are under, and third-party.json, the
# machine-readable manifest both were generated from.
#
#   usage: emit-third-party-kit.sh <macos|linux|windows> [bundle-dir]
#
# Environment:
#   THIRD_PARTY_BINARY_TAG    The release tag this pack ships under
#                             (binaries-…). Defaults to the BINARY_TAG
#                             file at the repository root, which is what
#                             _release-publish.yml checks the pushed tag
#                             against. Required one way or the other:
#                             THIRD-PARTY.md links the build scripts at
#                             that tag, and a kit that cannot say which
#                             scripts built it is not written at all.
#   THIRD_PARTY_ARCHIVE_NAME  Optional archive basename, e.g.
#                             notcurses-windows-x86_64, named in the
#                             document so a reader holding the extracted
#                             files can tell which of the two packs that
#                             share a platform key they have.
#   THIRD_PARTY_MANIFEST, THIRD_PARTY_LICENSE_DIR
#                             Overrides for local reproduction.
#   GITHUB_REF                When this is a tag ref (a release run), it
#                             must name the same tag.
#
# All three are generated from resources/third-party.json so the
# document and the gate can never disagree — scripts/ci/audit-third-party.sh
# reads the same file, and it runs immediately after this script does,
# over the pack this script has just added files to.
#
# Why this ships INSIDE the archive rather than only living in the
# repository: the archive is what a user actually receives. The
# permissive licences in it (BSD-2, BSD-3, MIT, X11, Zlib, the
# mingw-w64 runtime's notices on Windows) all require their copyright
# notice and licence text to accompany a binary redistribution, FFmpeg's
# Independent JPEG Group code requires an acknowledgement in the
# documentation, and the copyleft ones (FFmpeg's LGPL-2.1,
# libunistring's LGPL-3.0, and libiconv's LGPL-2.1 in the Windows
# packs) require the recipient be told of their rights and where the
# source is. A file in a git repository the user has never visited
# discharges none of that; a file next to the .so they just downloaded
# does.
#
# The document describes the archive it is written into, not the
# platform in general: every component is listed with the files that
# actually matched its patterns in bundle-dir, so the two Windows packs
# (which share the `windows` key) each list only what they hold. A
# component statically linked into another file — libvpx inside
# avcodec on Windows, the mingw-w64 runtime inside every DLL — is
# marked `embedded` in the manifest and listed against the files that
# contain it. A required component with no file, or an embedded one
# whose host is missing, is a hard error: the kit would otherwise
# describe a pack that does not exist.
#
# PORTABILITY: runs on the build lanes' HOST runners, not inside the
# manylinux/Alpine containers: ubuntu-22.04 (bash 5.1, jq 1.6),
# macos-14 (`shell: bash` is /bin/bash 3.2) and MSYS2 (bash 5.2, the
# MSYS jq package). So: no `mapfile`, no `declare -A`, array
# expansions guarded for `set -u`, and nothing from jq newer than 1.6
# (no `pick`, `trim`, `abs` or `toarray`, and every `if` has an
# `else`).
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

# `bundle/` and `bundle` must name the same pack-relative paths: BSD
# find prints `bundle//x` for the former.
while [[ "$BUNDLE_DIR" == */ && "$BUNDLE_DIR" != / ]]; do
    BUNDLE_DIR="${BUNDLE_DIR%/}"
done

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

# ---------------------------------------------------------------- #
# Release tag, and the URLs that hang off it
# ---------------------------------------------------------------- #
tag="${THIRD_PARTY_BINARY_TAG:-}"
tag_origin="THIRD_PARTY_BINARY_TAG"
if [[ -z "$tag" ]]; then
    tag_file="$REPO_ROOT/BINARY_TAG"
    if [[ ! -f "$tag_file" ]]; then
        echo "❌ No release tag: THIRD_PARTY_BINARY_TAG is unset and" >&2
        echo "   '$tag_file' does not exist. THIRD-PARTY.md links the scripts" >&2
        echo "   that built this pack at the tag it is released under; without" >&2
        echo "   one the kit cannot say where its build scripts are." >&2
        exit 1
    fi
    tag="$(tr -d '[:space:]' < "$tag_file")"
    tag_origin="$tag_file"
    if [[ -z "$tag" ]]; then
        echo "❌ No release tag: '$tag_file' is empty." >&2
        exit 1
    fi
fi
case "$tag" in
    binaries-*[!A-Za-z0-9._-]*|binaries-|'')
        tag_ok=0 ;;
    binaries-*)
        tag_ok=1 ;;
    *)
        tag_ok=0 ;;
esac
if (( tag_ok == 0 )); then
    echo "❌ Release tag '${tag}' (from $tag_origin) is not a binaries-<…> tag" >&2
    echo "   of letters, digits, '.', '_' and '-'." >&2
    exit 1
fi
# A release run is a pushed binaries-* tag (the only kind release.yml
# publishes from); the kit must link the scripts at THAT tag, which
# _release-publish.yml separately insists equals BINARY_TAG. Failing
# here as well means a mismatch stops the lane that would have packed
# the wrong link, rather than the publish job an hour later.
case "${GITHUB_REF:-}" in
    refs/tags/binaries-*)
        pushed="${GITHUB_REF#refs/tags/}"
        if [[ "$pushed" != "$tag" ]]; then
            echo "❌ This run is for tag '$pushed', but the kit would name '$tag'" >&2
            echo "   (from $tag_origin). Bump BINARY_TAG to the tag being pushed." >&2
            exit 1
        fi ;;
esac

archive="${THIRD_PARTY_ARCHIVE_NAME:-}"
case "$archive" in
    *[!A-Za-z0-9._-]*)
        echo "❌ THIRD_PARTY_ARCHIVE_NAME '$archive' is not a bare archive basename." >&2
        exit 1 ;;
esac

# The repository the kit links into is this distribution's own entry in
# the manifest, so a fork that renames itself fixes one place.
repo_url="$(jq -r '[ .components[] | select(.id == "notcurses-native") | .source.url ][0] // ""' "$MANIFEST")"
repo_url="${repo_url%/}"
repo_url="${repo_url%.git}"
case "$repo_url" in
    https://github.com/?*/?*) ;;
    *)
        echo "❌ The manifest's notcurses-native source.url ('$repo_url') is not a" >&2
        echo "   GitHub repository URL; the kit links release and build-script" >&2
        echo "   pages under it." >&2
        exit 1 ;;
esac
release_url="$repo_url/releases/tag/$tag"
scripts_url="$repo_url/tree/$tag/scripts/ci"
workflows_url="$repo_url/tree/$tag/.github"

# ---------------------------------------------------------------- #
# What the manifest says about this platform
# ---------------------------------------------------------------- #
# One record per component: id, required, embedded, patterns,
# embedded-in. Separated by US (0x1f) rather than tab: two of the
# fields are legitimately empty, and tab is IFS whitespace, so `read`
# would collapse an empty field and shift the rest left.
US=$'\037'
TAB=$'\t'
NL=$'\n'
comp_ids=()
comp_required=()
comp_embedded=()
comp_patterns=()
comp_hosts=()
while IFS="$US" read -r id required embedded patterns hosts; do
    [[ -n "$id" ]] || continue
    comp_ids+=( "$id" )
    comp_required+=( "$required" )
    comp_embedded+=( "$embedded" )
    comp_patterns+=( "$patterns" )
    comp_hosts+=( "$hosts" )
done < <(
    jq -r --arg p "$PLATFORM" '
        .components[]
        | (.binaries[$p] // {}) as $b
        | [ .id,
            (($b.required // false) | tostring),
            (($b.embedded // false) | tostring),
            (($b.patterns // []) | join(" ")),
            (($b["embedded-in"] // []) | join(" "))
          ]
        | join("\u001f")
    ' "$MANIFEST"
)

if (( ${#comp_ids[@]} == 0 )); then
    echo "❌ Manifest lists no components — is '$MANIFEST' the right file?" >&2
    exit 1
fi

# t/17 holds the manifest to these rules; checked again here because
# this script is what turns a malformed entry into a shipped document.
fail=0
i=0
while (( i < ${#comp_ids[@]} )); do
    if [[ "${comp_embedded[$i]}" == "true" ]]; then
        if [[ -n "${comp_patterns[$i]// /}" || -z "${comp_hosts[$i]// /}" \
              || "${comp_required[$i]}" == "true" ]]; then
            echo "❌ Component '${comp_ids[$i]}' is embedded on $PLATFORM, so it needs" >&2
            echo "   embedded-in globs, no patterns of its own and required false." >&2
            fail=1
        fi
    elif [[ -n "${comp_hosts[$i]// /}" ]]; then
        echo "❌ Component '${comp_ids[$i]}' names embedded-in on $PLATFORM but is not embedded." >&2
        fail=1
    fi
    i=$(( i + 1 ))
done
if (( fail != 0 )); then
    exit 1
fi

# Licence texts for every component that can appear here: a file
# pattern for this platform, or embedded on it. Note this is "can
# appear", not "did appear": the two Windows compiler runtimes are
# mutually exclusive per subsystem and several components are
# optional, but the set of texts a pack carries should be a property
# of the platform, not of which DLLs the linker happened to pull in on
# the day. A licence text nobody needed is inert; a missing one is a
# notice we failed to give. THIRD-PARTY.md names the optional
# components a given archive turned out not to hold, so every text in
# LICENSES/ is accounted for there.
licenses=()
while IFS= read -r lic; do
    [[ -n "$lic" ]] && licenses+=( "$lic" )
done < <(
    jq -r --arg p "$PLATFORM" '
        [ .components[]
          | (.binaries[$p] // {}) as $b
          | select((($b.patterns // []) | length) > 0 or ($b.embedded // false))
          | ."license-files"[] ]
        | unique | .[]
    ' "$MANIFEST"
)
if (( ${#licenses[@]} == 0 )); then
    echo "❌ No component in the manifest ships on '$PLATFORM' — that cannot be right." >&2
    exit 1
fi
for lic in "${licenses[@]}"; do
    if [[ ! -f "$LICENSE_DIR/$lic" ]]; then
        echo "❌ Manifest references licence text '$lic', which is not in $LICENSE_DIR." >&2
        exit 1
    fi
done

# ---------------------------------------------------------------- #
# What is actually in the archive
# ---------------------------------------------------------------- #
# A kit left by an earlier run must never survive into this one: if
# this run fails, the pack has no kit, which the lane's next steps
# catch, rather than a stale one, which nothing would.
license_out="$BUNDLE_DIR/LICENSES"
rm -rf "$license_out"
rm -f "$BUNDLE_DIR/THIRD-PARTY.md" "$BUNDLE_DIR/third-party.json"

# The pack's file list as it will be once the kit is written: what is
# there now, plus the kit's own files. Symlinks count (the macOS packs
# ship libnotcurses.dylib -> libnotcurses.3.0.17.dylib) exactly as in
# audit-third-party.sh, which this list has to agree with.
unsorted=()
while IFS= read -r f; do
    unsorted+=( "${f#"$BUNDLE_DIR"/}" )
done < <(find "$BUNDLE_DIR" -mindepth 1 \( -type f -o -type l \) -print)
for lic in "${licenses[@]}"; do
    unsorted+=( "LICENSES/$lic" )
done
unsorted+=( "THIRD-PARTY.md" "third-party.json" )
files=()
while IFS= read -r f; do
    files+=( "$f" )
done < <(printf '%s\n' "${unsorted[@]}" | LC_ALL=C sort -u)

# Same matcher as audit-third-party.sh: a pattern with a slash is
# matched against the whole relative path (LICENSES/*), one without
# against the basename.
path_matches() {
    local rel="$1" pat="$2"
    case "$pat" in
        */*)
            # shellcheck disable=SC2053  # RHS is a glob on purpose
            [[ "$rel" == $pat ]] && return 0 ;;
        *)
            # shellcheck disable=SC2053  # RHS is a glob on purpose
            [[ "${rel##*/}" == $pat ]] && return 0 ;;
    esac
    return 1
}

# Pattern lists are split on whitespace by iterating them unquoted;
# `set -f` stops them also being pathname-expanded against the cwd
# (see the same note in audit-third-party.sh for how that bites).
set -f

# Resolution records for jq, one per line, tab-separated:
#   F <id> <path>   a file of this component's own
#   H <id> <path>   a file this embedded component is compiled into
#   A <id>          an optional component with nothing in this archive
records=""
fail=0
i=0
while (( i < ${#comp_ids[@]} )); do
    id="${comp_ids[$i]}"
    required="${comp_required[$i]}"
    embedded="${comp_embedded[$i]}"
    patterns="${comp_patterns[$i]}"
    hosts="${comp_hosts[$i]}"
    i=$(( i + 1 ))

    if [[ "$embedded" == "true" ]]; then
        count=0
        for rel in ${files[@]+"${files[@]}"}; do
            for pat in $hosts; do
                if path_matches "$rel" "$pat"; then
                    records+="H${TAB}${id}${TAB}${rel}${NL}"
                    count=$(( count + 1 ))
                    break
                fi
            done
        done
        if (( count == 0 )); then
            echo "::error::component '$id' is embedded in $hosts on $PLATFORM, but nothing in $BUNDLE_DIR matches — the kit would name a host file this pack does not have"
            fail=1
        fi
        continue
    fi

    # No pattern for this platform: somebody else's component.
    [[ -n "${patterns// /}" ]] || continue

    count=0
    for rel in ${files[@]+"${files[@]}"}; do
        for pat in $patterns; do
            if path_matches "$rel" "$pat"; then
                records+="F${TAB}${id}${TAB}${rel}${NL}"
                count=$(( count + 1 ))
                break
            fi
        done
    done
    if (( count > 0 )); then
        continue
    fi
    if [[ "$required" == "true" ]]; then
        echo "::error::component '$id' is required on $PLATFORM but nothing in $BUNDLE_DIR matches its patterns: $patterns"
        fail=1
    else
        records+="A${TAB}${id}${NL}"
    fi
done
set +f

if (( fail != 0 )); then
    echo "❌ Not writing a licensing kit for a pack the manifest does not describe." >&2
    echo "   Either the bundling step lost a library (the pack is broken) or" >&2
    echo "   the manifest has stopped being true; fix whichever it is." >&2
    exit 1
fi

# ---------------------------------------------------------------- #
# LICENSES/
# ---------------------------------------------------------------- #
mkdir -p "$license_out"
for lic in "${licenses[@]}"; do
    cp "$LICENSE_DIR/$lic" "$license_out/$lic"
done
echo "Wrote ${#licenses[@]} licence text(s) to $license_out/"

# Shared jq preamble: the resolution records, and the lookups both
# documents are built from.
JQ_DEFS='
    ($records | split("\n") | map(select(length > 0) | split("\t"))) as $rows
    | def files_of($id): [ $rows[] | select(.[0] == "F" and .[1] == $id) | .[2] ];
      def hosts_of($id): [ $rows[] | select(.[0] == "H" and .[1] == $id) | .[2] ];
      def absent_ids: [ $rows[] | select(.[0] == "A") | .[1] ];
      def shipped: [ .components[]
                     | select((files_of(.id) | length) > 0 or (hosts_of(.id) | length) > 0) ];
      def ticks: map("`\(.)`") | join(", ");
'

# ---------------------------------------------------------------- #
# third-party.json
# ---------------------------------------------------------------- #
# The manifest itself, plus a `pack` block saying what this archive
# holds. Consumers that bundle the pack (App::Ariza) read this rather
# than parsing THIRD-PARTY.md.
json="$BUNDLE_DIR/third-party.json"
jq --arg p "$PLATFORM" --arg tag "$tag" --arg archive "$archive" \
   --arg release "$release_url" --arg scripts "$scripts_url" \
   --arg workflows "$workflows_url" --arg records "$records" "$JQ_DEFS"'
    . + { pack: {
            "_comment": [
              "Written by scripts/ci/emit-third-party-kit.sh into the archive",
              "this file came in; everything above this key is the manifest the",
              "archive was built against, unchanged. `components` lists, in",
              "manifest order, each component present in this archive with the",
              "files that matched its patterns, or, for an embedded component,",
              "the files it is compiled into (`embedded-in`). `absent` lists the",
              "optional components that can appear on this platform but are not",
              "in this archive; their licence texts are in LICENSES/ anyway."
            ],
            platform: $p,
            archive: (if $archive == "" then null else $archive end),
            "binary-tag": $tag,
            release: $release,
            "build-scripts": [ $scripts, $workflows ],
            components: [ shipped[]
                          | .id as $id
                          | { id: $id, files: files_of($id) }
                            + (if (hosts_of($id) | length) > 0
                               then { "embedded-in": hosts_of($id) }
                               else {} end) ],
            absent: absent_ids
          } }
' "$MANIFEST" > "$json.tmp"
mv "$json.tmp" "$json"
echo "Wrote $json"

# ---------------------------------------------------------------- #
# THIRD-PARTY.md
# ---------------------------------------------------------------- #
md="$BUNDLE_DIR/THIRD-PARTY.md"

{
    printf '# Third-party components in this package\n\n'
    printf '* Platform: `%s`\n' "$PLATFORM"
    if [[ -n "$archive" ]]; then
        printf '* Archive: `%s`\n' "$archive"
    fi
    printf '* Release: [`%s`](%s)\n' "$tag" "$release_url"
    printf '* Build scripts: <%s>, run by the workflows and actions under <%s>\n\n' \
        "$scripts_url" "$workflows_url"
    cat <<'PREAMBLE'
This archive is a binary redistribution. Everything it contains is
listed below with the licence it is conveyed under and the exact
source it was built from, and every file in it is named under the
component it belongs to. A component compiled into another file
rather than shipped as a file of its own is listed against the files
that contain it. Full licence texts are in `LICENSES/` alongside this
file, and `third-party.json` beside it is the machine-readable
manifest this document was generated from.

Where the source is given as a tarball URL with a SHA-256, that exact
tarball is attached to the GitHub release named above, so the
corresponding source for these binaries stays available for as long
as the binaries do. That is a requirement of the LGPL for FFmpeg,
GNU libunistring and — in the Windows archives, the only ones that
carry it — GNU libiconv; the other tarballs are attached for
consistency, so that "which source built this?" has one answer for
every component rather than two kinds of answer. The scripts that
built these binaries from those tarballs, which the LGPL counts as
part of the corresponding source, are linked above at the same
release tag.

FFmpeg here is a decoder-only build with neither `--enable-gpl` nor
`--enable-nonfree`, so it is conveyed under the LGPL v2.1 or later and
none of FFmpeg's GPL-only components are compiled in.

PREAMBLE
    printf '## Summary\n\n'
    printf '| Component | Version | Licence (SPDX) | Source |\n'
    printf '|---|---|---|---|\n'
    jq -r --arg p "$PLATFORM" --arg records "$records" "$JQ_DEFS"'
        shipped[]
        | . as $c
        | ( if   $c.source.kind == "tarball"         then "[tarball](\($c.source.url))"
            elif $c.source.kind == "git"             then "[git](\($c.source.url)) @ `\($c.source.ref)`"
            elif $c.source.kind == "in-tree"         then "[this project](\($c.source.url))"
            else "platform package manager"
            end ) as $src
        | "| \($c.name) | \($c.version) | `\($c["spdx-license"])` | \($src) |"
    ' "$MANIFEST"
    jq -r --arg p "$PLATFORM" --arg records "$records" "$JQ_DEFS"'
        absent_ids as $absent
        | if ($absent | length) == 0 then empty
          else
            ( "",
              "## Not in this archive",
              "",
              "These components can appear in `\($p)` archives but have no file in",
              "this one. Their licence texts are in `LICENSES/` all the same: every",
              "`\($p)` archive carries the same set of texts, whichever of these its",
              "build turned out to need.",
              "",
              ( .components[]
                | select(.id as $id | $absent | index([$id]))
                | "* \(.name) (`\(.["spdx-license"])`): none of "
                  + (.binaries[$p].patterns | ticks) + " is in this archive." ) )
          end
    ' "$MANIFEST"
    printf '\n## Details\n'
    jq -r --arg p "$PLATFORM" --arg release "$release_url" --arg records "$records" "$JQ_DEFS"'
        shipped[]
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
                  "* Attached to [the release](\($release)) as `\($c.source.filename)`" ]
              elif $c.source.kind == "git" then
                [ "* Source: <\($c.source.url)> at commit `\($c.source.ref)`" ]
              elif $c.source.kind == "in-tree" then
                [ "* Source: <\($c.source.url)>" ]
              else
                [ "* Source: supplied by the package manager of the build platform" ]
              end )
          + ( if (hosts_of($c.id) | length) > 0 then
                [ "* Embedded in: " + (hosts_of($c.id) | ticks)
                  + " — statically linked into "
                  + (if (hosts_of($c.id) | length) == 1 then "that file" else "each of those files" end)
                  + "; \($c.name) has no file of its own in this archive" ]
              else
                [ "* Files in this archive: " + (files_of($c.id) | ticks) ]
              end )
          + ( if $c.notes then [ "", $c.notes ] else [] end )
        | .[]
    ' "$MANIFEST"
    cat <<'FOOTER'

---

Generated from `resources/third-party.json` by
`scripts/ci/emit-third-party-kit.sh`. Do not edit this file by hand — edit
the manifest, which `scripts/ci/audit-third-party.sh` enforces against the
actual contents of this archive on every release. The manifest ships
beside this file as `third-party.json`, with a `pack` block recording
which files and embedded components this archive holds.
FOOTER
} > "$md"

shipped_count="$(jq -r --arg records "$records" "$JQ_DEFS"' shipped | length' "$MANIFEST")"
echo "Wrote $md ($(wc -l < "$md" | tr -d ' ') lines) for $shipped_count component(s) in this archive"
