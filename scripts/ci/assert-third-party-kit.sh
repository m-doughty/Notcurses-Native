#!/usr/bin/env bash
# Release gate: the licensing kit is in the pack, and in the archive
# made from it.
#
#   usage: assert-third-party-kit.sh <macos|linux|windows> <bundle-dir> <archive>
#
# Runs in .github/actions/package-and-upload after the archive has been
# written and before it is uploaded, so a failure here means no
# artefact for the publish job to collect.
#
# Why audit-third-party.sh is not enough on its own: its `required`
# check passes as soon as ONE of a component's patterns matches, and
# notcurses-native's patterns cover the perf shim as well as the kit.
# A pack that had lost THIRD-PARTY.md, third-party.json or every
# licence text would still pass it on the strength of the shim — and
# that pack is a binary redistribution of LGPL and BSD code with none
# of the notices those licences require. This checks the three by
# name, checks that they say what they should (the manifest copy
# parses and describes this platform and release, every licence text
# THIRD-PARTY.md cites is there), and then checks the archive itself,
# because the archive is what a user receives.
#
# PORTABILITY: same constraints as the other two kit scripts — bash
# 3.2 on macOS, jq 1.6 on ubuntu-22.04, MSYS2 on Windows, where the
# lane installs Info-ZIP `zip` but not `unzip`, so a zip is listed with
# `zip -sf` when `unzip` is absent. Every match uses a here-string,
# never `printf … | grep -q`: under `set -o pipefail` grep -q's early
# exit SIGPIPEs the producer, and a gate that found what it looked for
# would read that as failure.
set -euo pipefail

PLATFORM="${1:-}"
BUNDLE_DIR="${2:-}"
ARCHIVE="${3:-}"

case "$PLATFORM" in
    macos|linux|windows) ;;
    *)
        echo "usage: $0 <macos|linux|windows> <bundle-dir> <archive>" >&2
        echo "  (got platform '${PLATFORM:-<nothing>}')" >&2
        exit 2 ;;
esac
if [[ -z "$BUNDLE_DIR" || -z "$ARCHIVE" ]]; then
    echo "usage: $0 <macos|linux|windows> <bundle-dir> <archive>" >&2
    exit 2
fi
while [[ "$BUNDLE_DIR" == */ && "$BUNDLE_DIR" != / ]]; do
    BUNDLE_DIR="${BUNDLE_DIR%/}"
done
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is not on PATH — cannot read the pack's third-party.json." >&2
    exit 1
fi
if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "❌ Bundle directory '$BUNDLE_DIR' does not exist." >&2
    exit 1
fi
if [[ ! -f "$ARCHIVE" ]]; then
    echo "❌ Archive '$ARCHIVE' does not exist." >&2
    exit 1
fi

echo "--- licensing kit ($PLATFORM, $BUNDLE_DIR, $ARCHIVE) ---"
fail=0

md="$BUNDLE_DIR/THIRD-PARTY.md"
json="$BUNDLE_DIR/third-party.json"
lic_dir="$BUNDLE_DIR/LICENSES"

for f in "$md" "$json"; do
    if [[ ! -f "$f" || ! -s "$f" ]]; then
        echo "::error file=$f::missing or empty — the pack would ship without its licensing kit"
        fail=1
    fi
done

texts=()
if [[ -d "$lic_dir" ]]; then
    while IFS= read -r t; do
        texts+=( "LICENSES/${t##*/}" )
    done < <(find "$lic_dir" -mindepth 1 -maxdepth 1 -type f -name '*.txt' -size +0 -print | LC_ALL=C sort)
fi
if (( ${#texts[@]} == 0 )); then
    echo "::error file=$lic_dir::no licence texts — the pack would ship binaries without the licences they are under"
    fail=1
fi

if (( fail != 0 )); then
    echo "❌ The licensing kit is not in $BUNDLE_DIR. emit-third-party-kit.sh writes"
    echo "   it; check that its step ran and succeeded."
    exit 1
fi

# The manifest copy: parses, is the schema the consumers read, and its
# pack block describes this platform and a binaries-* release.
if ! jq -e --arg p "$PLATFORM" '
        .["schema-version"] == 1
        and ((.components | type) == "array") and ((.components | length) > 0)
        and .pack.platform == $p
        and ((.pack["binary-tag"] | type) == "string")
        and (.pack["binary-tag"] | startswith("binaries-"))
        and ((.pack.components | type) == "array") and ((.pack.components | length) > 0)
    ' "$json" >/dev/null; then
    echo "::error file=$json::does not parse as this platform's manifest copy (schema-version 1, a pack block for '$PLATFORM' naming a binaries-* tag)"
    fail=1
else
    tag="$(jq -r '.pack["binary-tag"]' "$json")"
    if ! grep -qF -- "$tag" < "$md"; then
        echo "::error file=$md::does not name the release '$tag' its third-party.json was written for"
        fail=1
    fi
    echo "ok: third-party.json describes $PLATFORM at $tag"
fi

# Every licence text THIRD-PARTY.md points a reader at is actually in
# the pack, and so is every text a component present in this archive
# names in the manifest.
cited=()
while IFS= read -r c; do
    [[ -n "$c" ]] && cited+=( "$c" )
done < <(
    {
        grep -o 'LICENSES/[A-Za-z0-9._+-]*\.txt' "$md" || true
        jq -r '
            [ .pack.components[].id ] as $ids
            | .components[]
            | select(.id as $id | ($ids | map(. == $id) | any))
            | ."license-files"[]
            | "LICENSES/\(.)"
        ' "$json" 2>/dev/null || true
    } | LC_ALL=C sort -u
)
if (( ${#cited[@]} == 0 )); then
    echo "::error file=$md::cites no licence text at all"
    fail=1
fi
for c in ${cited[@]+"${cited[@]}"}; do
    if [[ ! -s "$BUNDLE_DIR/$c" ]]; then
        echo "::error file=$md::cites $c, which is not in the pack"
        fail=1
    fi
done
echo "ok: ${#texts[@]} licence text(s) in LICENSES/, ${#cited[@]} cited"

# The archive. Entry names are normalised to the pack-relative form:
# `tar -C bundle .` stores `./THIRD-PARTY.md`, `zip -r` from inside
# the bundle stores `THIRD-PARTY.md`.
case "$ARCHIVE" in
    *.tar.gz|*.tgz)
        if ! raw="$(tar -tzf "$ARCHIVE")"; then
            echo "::error file=$ARCHIVE::could not be listed"
            exit 1
        fi ;;
    *.zip)
        if command -v unzip >/dev/null 2>&1; then
            if ! raw="$(unzip -Z1 "$ARCHIVE")"; then
                echo "::error file=$ARCHIVE::could not be listed"
                exit 1
            fi
        elif command -v zip >/dev/null 2>&1; then
            # Info-ZIP's "show files": a header line, one two-space
            # indented entry per line, and a "Total" line.
            if ! shown="$(zip -sf "$ARCHIVE")"; then
                echo "::error file=$ARCHIVE::could not be listed"
                exit 1
            fi
            raw="$(sed -n 's/^  //p' <<< "$shown")"
        else
            echo "❌ Neither unzip nor zip is on PATH — cannot list $ARCHIVE." >&2
            exit 1
        fi ;;
    *)
        echo "❌ Don't know how to list '$ARCHIVE' (expected .tar.gz or .zip)." >&2
        exit 1 ;;
esac
listing="$(sed -e 's|^\./||' <<< "$raw")"

for entry in THIRD-PARTY.md third-party.json ${texts[@]+"${texts[@]}"}; do
    if ! grep -qFx -- "$entry" <<< "$listing"; then
        echo "::error file=$ARCHIVE::has no $entry"
        fail=1
    fi
done

if (( fail != 0 )); then
    echo
    echo "❌ This archive would ship without part of its licensing kit"
    echo "   (THIRD-PARTY.md, third-party.json and LICENSES/). Every"
    echo "   permissive licence in it requires its notice to travel with"
    echo "   the binaries, and the LGPL requires the recipient be told"
    echo "   where the source is; an archive without the kit does neither."
    exit 1
fi
echo "✅ $(basename "$ARCHIVE") carries THIRD-PARTY.md, third-party.json and"
echo "   all ${#texts[@]} licence text(s)."
