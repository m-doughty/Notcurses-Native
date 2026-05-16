#!/usr/bin/env bash
# Install zef into the active rakubrew Rakudo. Runs AFTER the
# Rakudo cache save (so zef doesn't end up in the cached payload)
# but BEFORE any `zef install`. Takes ~30s.
#
# Why install zef every run instead of caching it: zef lives in
# `versions/moar-*/install/share/perl6/site/`, the same dir that
# zef tracks "already installed" state in. Caching site/ makes
# `zef install .` short-circuit with "All candidates are currently
# installed" on cache hit — Build.rakumod doesn't run, the
# Notcurses-Native prebuilt isn't staged into ~/.local/share/, and
# dlopen fails at test time. Cleaner to keep site/ out of the
# cache entirely and pay 30s/run for a guaranteed-fresh zef state.
#
# Honours $RAKUBREW_HOME (default $HOME/.rakubrew) — matches the
# default used by build-rakudo.sh.
set -euxo pipefail

export RAKUBREW_HOME="${RAKUBREW_HOME:-$HOME/.rakubrew}"
SHIM_DIR="$RAKUBREW_HOME/shims"

if [[ ! -x "$SHIM_DIR/raku" ]]; then
    echo "❌ No raku shim at $SHIM_DIR/raku — run build-rakudo.sh first" >&2
    exit 1
fi

# Prepend shims to PATH for this script. zef's installed wrapper at
# `site/bin/zef` does `exec rakudo "$@"` (not `exec raku`) and reads
# `rakudo` from PATH — without shims on PATH the wrapper fails with
# `exec: rakudo: not found`. The calling workflow step's PATH may
# not yet include shims (e.g., the `Add shims to PATH` step might
# run after this one), so be self-sufficient and prepend here.
export PATH="$SHIM_DIR:$PATH"

# Bootstrap zef directly from upstream — rakubrew's `build-zef`
# subcommand has a version-resolution bug ("Couldn't find version
# moar-X.Y" right after `build` produces it), so clone the repo
# and let raku self-install it via `bin/zef install .`. Standard
# upstream bootstrap recipe.
zef_src=$(mktemp -d)
trap 'rm -rf "$zef_src"' EXIT
git clone --depth=1 https://github.com/ugexe/zef.git "$zef_src"
(cd "$zef_src" && "$SHIM_DIR/raku" -I . bin/zef install .)

# zef installed into site/ → rakubrew needs to rehash so the shim
# at $SHIM_DIR/zef appears.
"$RAKUBREW_HOME/bin/rakubrew" rehash

"$SHIM_DIR/zef" --version
