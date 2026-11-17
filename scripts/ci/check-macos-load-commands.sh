#!/usr/bin/env bash
# The archive has a flat dylib directory. Every non-system import must
# already name a sibling via @loader_path before run paths can be removed.
set -euo pipefail

mode=${1:?expected --strip-rpaths or --verify}
bundle=${2:?expected bundle directory}
case "$mode" in
    --strip-rpaths|--verify) ;;
    *) echo "Unknown mode: $mode" >&2; exit 1 ;;
esac

fail() {
    echo "::error file=$file::$*" >&2
    exit 1
}

cd "$bundle"
for file in ./*.dylib; do
    [[ -f "$file" ]] || fail "missing dylib"
    if [[ -L "$file" ]]; then
        target=$(readlink "$file")
        case "$target" in
            */*|.*) fail "alias is not a sibling filename: $target" ;;
            *.dylib) ;;
            *) fail "alias does not target a dylib: $target" ;;
        esac
        [[ ! -L "./$target" && -f "./$target" ]] || fail "alias does not target a real sibling: $target"
        continue
    fi

    # Inspect the actual load commands so LC_ID_DYLIB is excluded even
    # when its name starts with @rpath. Include weak and re-export loads.
    commands=$(otool -l "$file")
    imports=$(awk '
        $1 == "cmd" { cmd = $2 }
        cmd ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB$/ && $1 == "name" {
            sub(/^[[:space:]]*name[[:space:]]+/, "")
            sub(/[[:space:]]+\(offset [0-9]+\)$/, "")
            print
        }
    ' <<< "$commands")
    while IFS= read -r import; do
        case "$import" in
            ""|/usr/lib/*|/System/Library/*) ;;
            @loader_path/*)
                sibling=${import#@loader_path/}
                case "$sibling" in
                    */*|.*) fail "import is not a sibling filename: $import" ;;
                    *.dylib) ;;
                    *) fail "import does not name a dylib: $import" ;;
                esac
                [[ -f "./$sibling" ]] || fail "missing sibling for $import"
                ;;
            *) fail "import is outside the relocated bundle or system libraries: $import" ;;
        esac
    done <<< "$imports"
done

status=0
for file in ./*.dylib; do
    [[ -L "$file" ]] && continue
    commands=$(otool -l "$file")
    rpaths=$(awk '
        $1 == "cmd" { cmd = $2 }
        cmd == "LC_RPATH" && $1 == "path" {
            sub(/^[[:space:]]*path[[:space:]]+/, "")
            sub(/[[:space:]]+\(offset [0-9]+\)$/, "")
            print
        }
    ' <<< "$commands")
    [[ -n "$rpaths" ]] || continue
    if [[ "$mode" == --verify ]]; then
        duplicates=$(sort <<< "$rpaths" | uniq -d)
        if [[ -n "$duplicates" ]]; then
            echo "::error file=$file::duplicate LC_RPATH: $duplicates" >&2
        else
            echo "::error file=$file::unexpected LC_RPATH: $rpaths" >&2
        fi
        status=1
        continue
    fi
    # install_name_tool removes one matching command per call, even
    # when dylibbundler has made several commands share the same path.
    while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" "$file"
    done <<< "$rpaths"
done
exit "$status"
