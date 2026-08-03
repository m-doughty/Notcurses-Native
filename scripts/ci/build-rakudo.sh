#!/usr/bin/env bash
# Source-build Rakudo via rakubrew. Used by verify lanes where
# Raku/setup-raku@v1 has no prebuilt for our target arch:
#
#   * macOS x86_64 (Intel/Rosetta — setup-raku gives arm64 Rakudo
#     on the macos-14 runner; we want x86_64 Rakudo under Rosetta).
#   * Linux glibc aarch64 (no aarch64 prebuilt in setup-raku).
#   * Linux musl x86_64 + aarch64 (Alpine's `apk add rakudo` is
#     too old to accept `Callable` in NativeCall's `is native(...)`
#     trait, which Notcurses::Native uses for lazy lib-path
#     resolution — apk's Rakudo fails to precompile our deps).
#   * Windows arm64 (no ARM64 prebuilt in setup-raku).
#
# Honours:
#   $RAKUDO_VERSION  — defaults to 2026.03. Pin in workflow env
#                      for cache-key stability.
#   $RAKUBREW_HOME   — defaults to $HOME/.rakubrew. actions/cache
#                      can persist this directory between runs so
#                      subsequent CI runs hit the ~10–20 min build.
#
# After the script completes, `raku` is accessible at
# `$RAKUBREW_HOME/shims/raku`. The calling workflow step is
# expected to:
#   1. Append `$RAKUBREW_HOME/shims` to $GITHUB_PATH.
#   2. Run `scripts/ci/install-zef.sh` to install zef fresh.
#
# zef is NOT installed by this script — it lives in
# `versions/moar-*/install/share/perl6/site/`, which is the same
# directory zef tracks "already installed" module state in.
# Caching that state turns `zef install` into a no-op on cache
# hit (Build.rakumod never runs). Cleaner to keep site/ out of
# the cache and pay 30s/run to install zef fresh.
#
# Idempotent — short-circuits if the target Rakudo is already
# built (cache hit OR previous failed-step rerun).
set -euxo pipefail

RAKUDO_VERSION="${RAKUDO_VERSION:-2026.03}"
export RAKUBREW_HOME="${RAKUBREW_HOME:-$HOME/.rakubrew}"
SHIM_DIR="$RAKUBREW_HOME/shims"

# Cache hit / already-installed short-circuit. Verify by asking
# the shim what version it reports — if it's our target, we're done.
if [[ -x "$SHIM_DIR/raku" ]] \
   && "$SHIM_DIR/raku" --version 2>/dev/null | grep -q "$RAKUDO_VERSION"; then
    echo "✅ Rakudo $RAKUDO_VERSION already installed at $RAKUBREW_HOME"
    "$SHIM_DIR/raku" --version
    exit 0
fi

mkdir -p "$RAKUBREW_HOME"

# Bootstrap rakubrew itself. The installer respects $RAKUBREW_HOME
# (exported above). install-on-perl.sh needs perl + curl, both
# universally available on every CI runner we use.
if [[ ! -x "$RAKUBREW_HOME/bin/rakubrew" ]]; then
    curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors https://rakubrew.org/install-on-perl.sh | sh
fi

# Switch to shim mode. rakubrew refuses to `build` if it's still
# in its default 'env' mode and no shell hook has been installed
# (the build command short-circuits with "The shell hook required
# to run rakubrew in either 'env' mode or with the 'shell' command
# seems not to be installed"). We have no interactive ~/.bashrc to
# source in CI, so shim mode — which drops dispatch wrappers into
# $RAKUBREW_HOME/shims/ as if it were a normal PATH dir — is the
# correct choice. Idempotent: re-running on a shim-mode rakubrew
# is a no-op.
"$RAKUBREW_HOME/bin/rakubrew" mode shim

# Build Rakudo with MoarVM backend. The first run takes ~10-20 min
# (NQP + MoarVM + Rakudo all from source); subsequent CI runs hit
# the actions/cache restore and skip this entirely.
"$RAKUBREW_HOME/bin/rakubrew" build "moar-$RAKUDO_VERSION"

# Activate the new version — `switch` sets the active version that
# the shims dispatch to.
"$RAKUBREW_HOME/bin/rakubrew" switch "moar-$RAKUDO_VERSION"

# Defensive — `build` already runs rehash internally per its
# "Updating shims" output, but explicit rehash makes sure the
# shim list is current even if rakubrew's logic changes.
"$RAKUBREW_HOME/bin/rakubrew" rehash

# Smoke check. zef is installed by install-zef.sh in the workflow
# after the cache save — it intentionally isn't part of this
# script (see header).
"$SHIM_DIR/raku" --version
