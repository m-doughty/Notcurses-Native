#!/usr/bin/env bash
# Release gate: every file in bundle/ is accounted for by
# resources/third-party.json, and every component that manifest says
# should be in this pack actually is.
#
#   usage: audit-third-party.sh <macos|linux|windows> [bundle-dir]
#
# Two failure directions, both of which have bitten this project in
# other forms:
#
#   1. An UNLISTED file. Something got swept into the pack that no
#      manifest entry describes — a new transitive dependency, a
#      package-manager library that came back, a stray build artefact.
#      We would be redistributing a binary whose licence nobody read,
#      whose notice we do not ship, and for which (were it copyleft)
#      we publish no corresponding source. That is exactly how the
#      whole x264/x265/SvtAv1Enc encoder tree ended up in the packs
#      while the lanes installed package-manager ffmpeg: nobody chose
#      it, it just arrived, and it took a licence audit to notice.
#
#   2. A MISSING component. A library the manifest says ships here is
#      not in the pack. Either the bundling walk lost it — in which
#      case the pack is broken at load time on a user's machine — or
#      it was deliberately dropped and the manifest is now lying. The
#      first is a release-blocking bug and the second is a document
#      that has stopped being true; both should stop the lane.
#
# Runs on the HOST, after bundling and after the licensing kit has
# been written into the pack — i.e. against exactly the file set the
# archive will contain. On the Linux lanes the bundle was produced by
# a container running as root; this only ever reads.
#
# PORTABILITY: this runs under GitHub's macOS images, where
# `shell: bash` is /bin/bash 3.2. No `mapfile`, no `declare -A`, and
# every array expansion is written `${a[@]+"${a[@]}"}` because an
# empty array under `set -u` is an error there. Parallel indexed
# arrays stand in for the hashes.
#
# Needs jq. GitHub's ubuntu-* and macos-* images ship it; the Windows
# lane installs the MSYS2 `jq` package (see setup-msys2's install
# list in _build-windows.yml).
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

# Manifest location is script-relative so this works from any cwd,
# with an env override for local reproduction against a pack pulled
# out of a published release.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${THIRD_PARTY_MANIFEST:-$SCRIPT_DIR/../../resources/third-party.json}"

if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is not on PATH — this gate cannot read the manifest." >&2
    echo "   Install it in this lane (apk/dnf/brew/pacman 'jq')." >&2
    exit 1
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "❌ Manifest not found at '$MANIFEST'." >&2
    exit 1
fi
if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "❌ Bundle directory '$BUNDLE_DIR' does not exist." >&2
    exit 1
fi

echo "--- third-party audit ($PLATFORM, $BUNDLE_DIR) ---"

# The pack's file list, as paths relative to the bundle root.
# Symlinks count: they are real entries in the published archive (the
# macOS packs ship libnotcurses.dylib -> libnotcurses.3.0.17.dylib),
# and an unaccounted-for symlink is just as much an unaccounted-for
# name as a regular file. Directories are not listed — a directory
# carries no licence — but their contents are, which is why the
# manifest spells LICENSES/* rather than LICENSES.
files=()
while IFS= read -r f; do
    files+=( "${f#"$BUNDLE_DIR"/}" )
done < <(find "$BUNDLE_DIR" -mindepth 1 \( -type f -o -type l \) -print | LC_ALL=C sort)

if (( ${#files[@]} == 0 )); then
    echo "❌ '$BUNDLE_DIR' contains no files — bundling did not run."
    exit 1
fi

# Parallel arrays, index-aligned: id / required flag / space-separated
# patterns for this platform / running match count.
#
# Field order is deliberate. `patterns` is the field that is legally
# empty (a component absent on this platform) and it is LAST because
# tab is an IFS-whitespace character: with IFS=$'\t', `read` collapses
# runs of tabs into one delimiter, so an empty field in the MIDDLE of
# the line silently shifts every field after it left by one. Putting
# the empty-able field last means the worst case is `read` assigning
# it the empty remainder, which is exactly what we want. (Spaces are
# not in IFS here, so the pattern list survives intact.)
comp_ids=()
comp_required=()
comp_patterns=()
comp_matches=()
while IFS=$'\t' read -r id required patterns; do
    comp_ids+=( "$id" )
    comp_required+=( "$required" )
    comp_patterns+=( "$patterns" )
    comp_matches+=( 0 )
done < <(
    jq -r --arg p "$PLATFORM" '
        .components[]
        | [ .id,
            ((.binaries[$p].required // false) | tostring),
            ((.binaries[$p].patterns // []) | join(" "))
          ]
        | @tsv
    ' "$MANIFEST"
)

if (( ${#comp_ids[@]} == 0 )); then
    echo "❌ Manifest lists no components — is '$MANIFEST' the right file?"
    exit 1
fi

# System libraries: allowed but not components. In normal operation
# none of these match anything, because nothing bundles a libc. See
# the manifest's `system-libraries` comment for why the list exists.
system_patterns="$(
    jq -r --arg p "$PLATFORM" \
        '(.["system-libraries"][$p] // []) | join(" ")' "$MANIFEST"
)"

# fnmatch a pack-relative path against one manifest pattern. A pattern
# containing a slash is matched against the whole relative path
# (LICENSES/*); one without is matched against the basename, which for
# everything at the pack root is the same string either way.
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

# Pattern lists are iterated unquoted below, which is how they get
# split on whitespace into individual patterns — and, without this,
# would ALSO get pathname-expanded against the current directory.
# That is not hypothetical: with a file named `libavcodec.so.99` in
# the cwd, `for pat in libavcodec.so.*` expands to that one literal
# name, the pattern stops being a glob, and the real
# `libavcodec.so.62` in the pack is reported as an unlisted file. The
# lane would fail on a licensing error that has nothing to do with
# licensing. `set -f` turns pathname expansion off for the rest of
# the script; `[[ x == $pat ]]` pattern matching is a separate
# mechanism and is unaffected.
set -f

fail=0
unmatched=()

for rel in ${files[@]+"${files[@]}"}; do
    matched_by=""
    i=0
    while (( i < ${#comp_ids[@]} )); do
        for pat in ${comp_patterns[$i]}; do
            if path_matches "$rel" "$pat"; then
                comp_matches[i]=$(( comp_matches[i] + 1 ))
                matched_by="${matched_by:+$matched_by, }${comp_ids[$i]}"
                break
            fi
        done
        i=$(( i + 1 ))
    done
    if [[ -n "$matched_by" ]]; then
        printf 'ok:     %-42s → %s\n' "$rel" "$matched_by"
        continue
    fi
    for pat in $system_patterns; do
        if path_matches "$rel" "$pat"; then
            matched_by="system-library"
            break
        fi
    done
    if [[ -n "$matched_by" ]]; then
        # Allowed, but say so loudly: nothing should be bundling a
        # platform C runtime, so this is a bundling bug we happen not
        # to be failing the release over.
        printf '::warning file=%s/%s::matches the %s system-library allow-list — it should not have been bundled at all\n' \
            "$BUNDLE_DIR" "$rel" "$PLATFORM"
        continue
    fi
    echo "::error file=$BUNDLE_DIR/$rel::not covered by any component in resources/third-party.json"
    unmatched+=( "$rel" )
    fail=1
done

echo "--- component presence ---"
i=0
while (( i < ${#comp_ids[@]} )); do
    id="${comp_ids[$i]}"
    patterns="${comp_patterns[$i]}"
    count="${comp_matches[$i]}"
    required="${comp_required[$i]}"
    # Incremented here, not at the bottom: several branches below
    # `continue`, and a bottom increment would loop forever on them.
    i=$(( i + 1 ))
    if [[ -z "${patterns// /}" ]]; then
        printf 'skip:   %-22s (not shipped on %s)\n' "$id" "$PLATFORM"
        continue
    fi
    if (( count > 0 )); then
        printf 'ok:     %-22s %d file(s)\n' "$id" "$count"
        continue
    fi
    if [[ "$required" == "true" ]]; then
        echo "::error::component '$id' is required on $PLATFORM but nothing in $BUNDLE_DIR matches its patterns: $patterns"
        fail=1
    else
        printf 'absent: %-22s (optional on %s)\n' "$id" "$PLATFORM"
    fi
done

if (( fail != 0 )); then
    echo
    if (( ${#unmatched[@]} > 0 )); then
        echo "❌ ${#unmatched[@]} file(s) in $BUNDLE_DIR are not described by"
        echo "   resources/third-party.json:"
        printf '     %s\n' ${unmatched[@]+"${unmatched[@]}"}
        echo
        echo "   Each one is a binary this project would be redistributing"
        echo "   without having read its licence, shipped its notice, or"
        echo "   published corresponding source for it. Work out where it"
        echo "   came from and either stop bundling it or add a component"
        echo "   entry — do NOT widen an existing pattern to swallow it."
    fi
    echo "   (Any 'component ... is required' error above means the"
    echo "   opposite problem: a library the manifest promises is in this"
    echo "   pack isn't.)"
    exit 1
fi

echo "✅ Third-party audit passed: every file in $BUNDLE_DIR is a known"
echo "   component, and every component due on $PLATFORM is present."
