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
# After the script completes:
#   $RAKUBREW_HOME/versions/moar-$RAKUDO_VERSION/bin
# is the Rakudo install directory containing `raku` and `zef`. The
# calling workflow step is expected to append it to $GITHUB_PATH.
#
# Idempotent — short-circuits if the target Rakudo is already
# built (cache hit OR previous failed-step rerun).
set -euxo pipefail

RAKUDO_VERSION="${RAKUDO_VERSION:-2026.03}"
export RAKUBREW_HOME="${RAKUBREW_HOME:-$HOME/.rakubrew}"

RAKU_BIN_DIR="$RAKUBREW_HOME/versions/moar-$RAKUDO_VERSION/bin"

# Install zef manually using the freshly-built (or cached) Raku.
# rakubrew has a `build-zef` action but it sometimes fails to find
# the version it just installed ("Couldn't find version moar-X.Y" —
# inconsistent version-resolution between `build` and `build-zef`
# observed empirically). Bypass by bootstrapping zef directly: clone
# the repo, then run zef-from-source to install zef-as-a-module.
# That's literally the official upstream bootstrap recipe.
install_zef() {
    if [[ -x "$RAKU_BIN_DIR/zef" ]]; then
        echo "  zef already present at $RAKU_BIN_DIR/zef"
        return 0
    fi
    local zef_src=/tmp/zef-bootstrap
    rm -rf "$zef_src"
    git clone --depth=1 https://github.com/ugexe/zef.git "$zef_src"
    (cd "$zef_src" && "$RAKU_BIN_DIR/raku" -I . bin/zef install .)
    rm -rf "$zef_src"
}

# Cache hit / already-installed short circuit.
if [[ -x "$RAKU_BIN_DIR/raku" ]]; then
    echo "✅ Rakudo $RAKUDO_VERSION already installed at $RAKUBREW_HOME"
    "$RAKU_BIN_DIR/raku" --version
    install_zef
    "$RAKU_BIN_DIR/zef" --version || true
    exit 0
fi

mkdir -p "$RAKUBREW_HOME"

# Bootstrap rakubrew itself. The installer respects $RAKUBREW_HOME
# (exported above). install-on-perl.sh needs perl + curl, both
# universally available on every CI runner we use.
if [[ ! -x "$RAKUBREW_HOME/bin/rakubrew" ]]; then
    curl -fsSL https://rakubrew.org/install-on-perl.sh | sh
fi

# Switch to shim mode. rakubrew refuses to `build` if it's still
# in its default 'env' mode and no shell hook has been installed
# (the build command short-circuits with "The shell hook required
# to run rakubrew in either 'env' mode or with the 'shell' command
# seems not to be installed"). We have no interactive ~/.bashrc to
# source in CI, so shim mode — which just drops binaries into
# $RAKUBREW_HOME/shims/ as if it were a normal PATH dir — is the
# correct choice. Idempotent: re-running on a shim-mode rakubrew
# is a no-op.
"$RAKUBREW_HOME/bin/rakubrew" mode shim

# Build Rakudo with MoarVM backend. The first run takes ~10-20 min
# (NQP + MoarVM + Rakudo all from source); subsequent CI runs hit
# the actions/cache restore and skip this entirely.
"$RAKUBREW_HOME/bin/rakubrew" build "moar-$RAKUDO_VERSION"

# Activate it (sets a `current` symlink rakubrew uses for `raku`
# shim resolution — irrelevant for our direct PATH-based usage,
# but harmless).
"$RAKUBREW_HOME/bin/rakubrew" switch "moar-$RAKUDO_VERSION"

# Install zef via the bootstrap helper defined above (replaces
# rakubrew's build-zef, which has a version-resolution bug).
install_zef

# Smoke check.
"$RAKU_BIN_DIR/raku" --version
"$RAKU_BIN_DIR/zef" --version
