#| Build.rakumod for Notcurses::Native.
#|
#| Two paths, tried in order:
#|
#|   1. Prebuilt binary archive download from GitHub Releases. One
#|      archive per platform contains libnotcurses, libnotcurses-core,
#|      libnotcurses-ffi, plus any ffmpeg sibling dylibs relocated to
#|      load from the same directory (@loader_path on macOS, $ORIGIN
#|      on Linux, and a flat dependency closure plus explicit loader
#|      search setup on Windows). Archive format is .tar.gz
#|      on Unix and .zip on Windows. SHA256 verified against bundled
#|      resources/checksums.txt. Typically ~15–40 MB unpacked
#|      (ffmpeg is most of the bulk).
#|
#|   2. Fallback: build notcurses from the vendored source via CMake.
#|      Needs cmake + a C toolchain + system-installed ffmpeg / ncurses
#|      / libunistring / libdeflate dev headers. Takes ~5–15 minutes
#|      depending on platform. See docs/Readme.rakudoc for per-distro
#|      install instructions.
#|
#| Why we don't use META6 resources for the libs:
#|
#|   zef hashes every staged resource filename to a SHA-keyed name in
#|   .../resources/. notcurses dylibs/sos/dlls have inter-dep references
#|   baked in via @loader_path / $ORIGIN, while Windows import tables
#|   retain the sibling DLL basenames
#|   (e.g. libnotcurses.dylib needs libnotcurses-core.3.0.17.dylib next
#|   to it on disk by that exact name). Renamed-to-hash files break
#|   those refs and the loader fails at first dlopen with cryptic
#|   "Library not loaded" errors. So instead Build.rakumod stages the
#|   libs to a stable XDG data dir under their real filenames, and
#|   Native.rakumod reads from there. Only BINARY_TAG (a tiny text
#|   file, no inter-file refs) goes through %?RESOURCES.
#|
#| Env-var knobs:
#|
#|   NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1  skip prebuilt, always compile
#|   NOTCURSES_NATIVE_BINARY_ONLY=1        refuse to fall back to compile
#|   NOTCURSES_NATIVE_BINARY_URL=<url>     override GH release base URL
#|   NOTCURSES_NATIVE_CACHE_DIR=<path>     override download cache dir
#|   NOTCURSES_NATIVE_DATA_DIR=<path>      override staged-libs dir
#|                                         (defaults to XDG_DATA_HOME)
#|   NOTCURSES_NATIVE_LIB_DIR=<path>       (runtime) load libs from this
#|                                         dir instead of the staged
#|                                         data dir
#|   NOTCURSES_NATIVE_VENDOR_DIR=<path>    use this local notcurses source
#|                                         tree instead of fetching the
#|                                         pinned commit from the fork at
#|                                         build time. Required for
#|                                         airgapped installs; also useful
#|                                         when iterating on the fork
#|                                         locally without push cycles.
#|                                         No SHA verification — caller
#|                                         is responsible for the tree.
#|
#| Linux prebuilts:
#|
#|   * glibc lanes are built in manylinux_2_28 containers
#|     (`quay.io/pypa/manylinux_2_28_{x86_64,aarch64}`, RHEL 8-era,
#|     glibc 2.28 floor — see the $MIN-GLIBC constant). On systems
#|     with older glibc the prebuilt libnotcurses / ffmpeg libs
#|     load but die at first symbol use with "GLIBC_2.xx not found".
#|     Build detects this via `ldd --version` and short-circuits to
#|     the CMake source build before the download even happens.
#|     glibc 2.28 covers every glibc distro under active maintenance
#|     in 2026 — RHEL 8+ / Ubuntu 18.10+ / Debian 10+. (manylinux2014
#|     / RHEL 7 / glibc 2.17 was retired by pypa in March 2025 and
#|     its CentOS 7 yum mirrors are decaying after the June 2024
#|     CentOS 7 EOL, so we're on the actively-maintained successor.)
#|
#|   * musl lanes are built in `alpine:3.20` containers (musl 1.2.5
#|     headers; practical runtime floor musl 1.20 per notcurses'
#|     declared support level, which Alpine 3.13+ satisfies). musl
#|     vs glibc is selected by the slug-map key — `!detect-libc`
#|     probes for `/lib/ld-musl-*.so.1` on disk.

class Build {

    # --- Constants ------------------------------------------------------

    constant $DEFAULT-BASE-URL =
        'https://github.com/m-doughty/Notcurses-Native/releases/download';

    # Source-built Windows DLLs retain ordinary MSYS2 runtime dependencies,
    # unlike release archives whose dependency closure is self-contained.
    # Keep that provenance beside the staged libraries so runtime loading can
    # select the corresponding Win32 search contract in a fresh process.
    constant $SOURCE-BUILD-MARKER = '.notcurses-native-source-build';

    # Minimum glibc the prebuilt Linux archives are compatible with.
    # The CI workflow builds inside manylinux_2_28 containers (RHEL 8
    # baseline, glibc 2.28); libnotcurses + sibling ffmpeg dylibs only
    # reference GLIBC_2.28-or-older versioned symbols, so they load
    # on every glibc Linux distro under active maintenance in 2026
    # (RHEL 8+ / Ubuntu 18.10+ / Debian 10+). Bump in lockstep with
    # the manylinux baseline if we ever rebase onto manylinux_2_34
    # (RHEL 9, glibc 2.34).
    constant $MIN-GLIBC = v2.28;

    # Map (platform key) → platform slug used in release artefact
    # filenames + cache paths.
    #
    # Key shape:
    #   * non-Linux: "<os>-<hardware>"           (e.g. "darwin-arm64")
    #   * Linux:     "<os>-<hardware>-<libc>"    (e.g. "linux-x86_64-musl")
    # `!detect-libc` only inspects the libc on Linux; everywhere else
    # the key is just `os-hardware`.
    #
    # macOS x86_64 is built on an arm64 GHA runner under Rosetta 2
    # (GitHub's `macos-13` native-x86_64 runner is deprecated and
    # arm64-with-Rosetta is the long-lived option); clang under
    # Rosetta emits ordinary x86_64 Mach-O that runs natively on real
    # Intel Macs and Hackintoshes. macOS x86_64 deployment target is
    # pinned at 10.15 (Catalina) so the artefact loads on every Intel
    # Mac Apple supports back to ~2012 hardware.
    #
    # Linux glibc lanes use manylinux_2_28 (RHEL 8, glibc 2.28 floor);
    # musl lanes use alpine:3.20 (musl 1.2.5 headers, 1.20+ runtime
    # floor).
    # Typed `Str` so missing-key lookups return the Str type object
    # (not Any), which satisfies `detect-platform`'s `--> Str` return
    # constraint and lets `without $plat { ... }` fire for any
    # genuinely-novel platform combo we don't ship binaries for.
    my Str %PLATFORM-SLUGS =
        'darwin-arm64'          => 'macos-arm64',
        'darwin-x86_64'         => 'macos-x86_64',
        'linux-x86_64-glibc'    => 'linux-x86_64-glibc',
        'linux-x86_64-musl'     => 'linux-x86_64-musl',
        'linux-aarch64-glibc'   => 'linux-aarch64-glibc',
        'linux-aarch64-musl'    => 'linux-aarch64-musl',
        'win32-x86_64'          => 'windows-x86_64',
        'win32-aarch64'         => 'windows-arm64',
        'mswin32-x86_64'        => 'windows-x86_64',
        'mswin32-aarch64'       => 'windows-arm64',
    ;

    # --- Entry point ----------------------------------------------------

    method build($dist-path) {
        my Bool $force-source = ?%*ENV<NOTCURSES_NATIVE_BUILD_FROM_SOURCE>;
        my Bool $binary-only  = ?%*ENV<NOTCURSES_NATIVE_BINARY_ONLY>;

        my Str $binary-tag = self!binary-tag($dist-path);
        my Str $plat = self.detect-platform;

        # Make BINARY_TAG available via %?RESOURCES so Native.rakumod
        # can find the corresponding staged-libs dir at runtime. This
        # is a tiny text file so it survives zef's resource-hashing
        # rename intact (we only ever read its contents).
        self!stage-binary-tag($dist-path);

        # Where the libs actually go. Stable XDG-style location, NOT
        # under the dist's resources/ — see header comment for why.
        my IO::Path $stage = self!staged-lib-dir($binary-tag);

        without $plat {
            my Str $tried = self.detect-platform-key;
            my Str $known = self.known-platform-keys.join(', ');
            my Str $libc = self.detect-libc // 'n/a';
            note qq:to/MSG/;
                ⚠️  Notcurses::Native has no prebuilt binary for this platform.
                    Tried lookup key: '$tried'
                        (\$*KERNEL.name='{$*KERNEL.name}',
                         \$*KERNEL.hardware='{$*KERNEL.hardware}',
                         libc='$libc')
                    Known platforms:  $known
                    Falling back to building notcurses from source via CMake.
                MSG
            self!compile-from-source($dist-path, $stage);
            self!try-compile-shim($dist-path, $stage);
            return True;
        }

        # Guard: prebuilt Linux archives are built on ubuntu-22.04
        # (glibc $MIN-GLIBC). On older glibc the downloaded libs load
        # but die at first symbol use with "GLIBC_2.xx not found".
        # Detect here and fall back to CMake source build before the
        # download even happens.
        if !$force-source && $plat.ends-with('-glibc') {
            my Version $have = self!detect-glibc-version;
            if $have.defined && $have cmp $MIN-GLIBC == Less {
                if $binary-only {
                    die "NOTCURSES_NATIVE_BINARY_ONLY=1 set but system "
                      ~ "glibc $have is older than prebuilt target "
                      ~ "$MIN-GLIBC ($plat / $binary-tag).";
                }
                note "⚠️  System glibc $have is older than prebuilt "
                   ~ "target $MIN-GLIBC — falling back to source build "
                   ~ "to avoid runtime loader errors.";
                self!compile-from-source($dist-path, $stage);
                say "✅ Compiled Notcurses from vendored source → $stage.";
                self!try-compile-shim($dist-path, $stage);
                return True;
            }
        }

        unless $force-source {
            if self!try-prebuilt($dist-path, $plat, $binary-tag, $stage) {
                say "✅ Installed prebuilt Notcurses binaries ($plat) for "
                  ~ "$binary-tag → $stage.";
                self!try-compile-shim($dist-path, $stage);
                self!cleanup-old-stages($stage);
                return True;
            }
            if $binary-only {
                die "NOTCURSES_NATIVE_BINARY_ONLY=1 set but prebuilt download "
                  ~ "failed for $plat ($binary-tag).";
            }
            note "⚠️  Prebuilt archive unavailable for $plat ($binary-tag) "
               ~ "— compiling from source via CMake.";
        }

        self!compile-from-source($dist-path, $stage);
        say "✅ Compiled Notcurses from vendored source → $stage.";
        self!try-compile-shim($dist-path, $stage);
        self!cleanup-old-stages($stage);
        True;
    }

    #|( Remove sibling staged dirs for older BINARY_TAGs. zef has no
        uninstall hook, and Build.rakumod is the only place we can
        garbage-collect obsolete staged bundles, so we do it here on
        every install: any sibling under the staged-libs root that
        looks like one of our `binaries-notcurses-*` dirs and isn't
        the currently-active one gets removed. Without this, an
        upgrade leaves the prior tag's libs on disk where stale
        Raku precomp can still load them, producing duplicate-load
        warnings (and worse on macOS — cf. the Vips::Native r7→r8
        upgrade where two libgio.dylibs got registered side-by-side).

        Set NOTCURSES_NATIVE_KEEP_OLD_STAGES=1 to disable. )
    method !cleanup-old-stages(IO::Path $current-stage --> Nil) {
        return if %*ENV<NOTCURSES_NATIVE_KEEP_OLD_STAGES>;

        # $current-stage layout is …/Notcurses-Native/<binary-tag>/lib.
        # The *tag* dir is one level up, the *root* (where sibling
        # tag dirs live) is two levels up.
        my $current-tag-dir = $current-stage.parent;
        my $root            = $current-tag-dir.parent;
        return unless $root.d;
        return unless $root.basename eq 'Notcurses-Native';

        my Str $current-abs = $current-tag-dir.absolute;

        for $root.dir -> $entry {
            next unless $entry.d;
            next unless $entry.basename.starts-with('binaries-notcurses-');
            next if $entry.absolute eq $current-abs;
            say "🧹 Removing orphaned staged dir: { $entry }";
            try {
                run 'rm', '-rf', $entry.Str;
                CATCH { default { note "  (failed to remove: { .message })" } }
            };
        }
    }

    # The XDG-style staged-libs dir for a given binary-tag. Versioned
    # so a downgrade lines up with the right libs and parallel-installed
    # versions (mid-upgrade etc.) don't trample each other.
    method !staged-lib-dir(Str $binary-tag --> IO::Path) {
        my Str $base = %*ENV<NOTCURSES_NATIVE_DATA_DIR>
            // %*ENV<XDG_DATA_HOME>
            // ($*DISTRO.is-win
                    ?? (%*ENV<LOCALAPPDATA>
                            // "{%*ENV<USERPROFILE> // '.'}\\AppData\\Local")
                    !! "{%*ENV<HOME> // '.'}/.local/share");
        "$base/Notcurses-Native/$binary-tag/lib".IO;
    }

    method !stage-binary-tag($dist-path) {
        my IO::Path $src = "$dist-path/BINARY_TAG".IO;
        my IO::Path $dst = "$dist-path/resources/BINARY_TAG".IO;
        $dst.parent.mkdir;
        copy $src, $dst;
    }

    method !remove-stage-entry(IO::Path $entry --> Nil) {
        if $entry.d && !$entry.l {
            self!remove-stage-entry($_) for $entry.dir;
            $entry.rmdir;
        }
        elsif $entry.e || $entry.l {
            $entry.unlink;
        }
    }

    # A binary tag can be reinstalled through the other provenance path.
    # Always start either install from an empty stage so a source build cannot
    # inherit a prebuilt FFmpeg closure, and a prebuilt cannot retain the
    # source marker (or any ordinary-PATH assumptions it represents).
    method !reset-stage(IO::Path $stage --> Nil) {
        if $stage.d {
            self!remove-stage-entry($_) for $stage.dir;
        }
        elsif $stage.e || $stage.l {
            die "❌ Staged library path exists but is not a directory: $stage";
        }
        $stage.mkdir;
    }

    method !mark-source-build(IO::Path $stage --> Nil) {
        $stage.add($SOURCE-BUILD-MARKER).spurt("source-build\n");
    }

    # --- Prebuilt binary pathing ----------------------------------------

    method !try-prebuilt($dist-path, Str $plat, Str $binary-tag, IO::Path $stage --> Bool) {
        my Str $artifact = self!artifact-name($plat);
        my IO::Path $cache-dir = self!cache-dir($binary-tag);
        my IO::Path $cached = $cache-dir.add($artifact);
        my Str $base-url = %*ENV<NOTCURSES_NATIVE_BINARY_URL> // $DEFAULT-BASE-URL;
        my Str $url = "$base-url/$binary-tag/$artifact";

        unless $cached.e {
            $cache-dir.mkdir;
            say "⬇️  Fetching $artifact from $url";
            my $rc = run 'curl', '-fL', '--progress-bar',
                         '-o', $cached.Str, $url;
            unless $rc.exitcode == 0 {
                $cached.unlink if $cached.e;
                return False;
            }
        }

        my Str $expected = self!expected-sha($dist-path, $artifact);
        without $expected {
            note "No checksum recorded for $artifact in resources/checksums.txt "
                ~ "— refusing prebuilt (bundled checksums are a hard security boundary).";
            return False;
        }

        my Str $actual = self!sha256($cached);
        unless $actual.defined && $actual.lc eq $expected.lc {
            my Str $tried = $actual.defined
                ?? ''
                !! ($*DISTRO.is-win
                        ?? ' (tried: certutil)'
                        !! ' (tried: sha256sum, shasum)');
            note "Checksum mismatch for $artifact "
                ~ "(expected $expected, got {$actual // 'unknown'}$tried).";
            $cached.unlink;
            return False;
        }

        self!extract-archive($cached, $stage);
        True;
    }

    method !artifact-name(Str $plat --> Str) {
        my Str $archive-ext = $plat.starts-with('windows') ?? 'zip' !! 'tar.gz';
        "notcurses-$plat.$archive-ext";
    }

    method !extract-archive(IO::Path $archive, IO::Path $dest) {
        # Wipe + recreate: avoid mixing files from a prior install of
        # the same tag (eg if the user manually swapped archives). Tag
        # dir is versioned so other versions are unaffected.
        self!reset-stage($dest);

        if $archive.Str.ends-with('.zip') {
            # Windows zip extraction via PowerShell. We deliberately
            # avoid `tar` here even though Win10+ ships bsdtar that
            # handles zips: if the user (or the install env, like
            # msys2 under CI) has GNU tar first on PATH, GNU tar
            # parses `D:\...` as a remote host (`host:path` syntax)
            # and bombs with "Cannot connect to D: resolve failed".
            # Expand-Archive has no such quirk and is available on
            # every Windows we support.
            my $rc = run 'powershell', '-NoProfile', '-Command',
                "Expand-Archive -LiteralPath '$archive' -DestinationPath '$dest' -Force";
            die "❌ Failed to extract $archive." unless $rc.exitcode == 0;
        }
        else {
            # .tar.gz — portable across macOS/Linux.
            my $rc = run 'tar', '-xzf', $archive.Str, '-C', $dest.Str;
            die "❌ Failed to extract $archive." unless $rc.exitcode == 0;
        }

        # Sanity-check: the three notcurses libs must be present post-extract.
        # Allow either the unversioned name or any versioned variant
        # (e.g. libnotcurses.3.dylib, libnotcurses.so.3) since the
        # archive is allowed to ship versioned files alongside the
        # unversioned symlinks. The runtime resolver in Native.rakumod
        # knows how to pick the right one.
        my Str $ext = $*KERNEL.name.lc ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            my @found = $dest.dir.grep({
                my $bn = .basename;
                $bn eq "$lib.$ext"
                    || ($bn.starts-with("$lib.") && $bn.contains(".$ext"))
                    || ($bn.starts-with("$lib-") && $bn.ends-with(".$ext"));
            });
            die "❌ Prebuilt archive missing expected lib: $lib.$ext"
                unless @found;
        }
    }

    method !cache-dir(Str $binary-tag --> IO::Path) {
        my Str $base = %*ENV<NOTCURSES_NATIVE_CACHE_DIR>
            // %*ENV<XDG_CACHE_HOME>
            // "{%*ENV<HOME> // '.'}/.cache";
        "$base/Notcurses-Native-binaries/$binary-tag".IO;
    }

    method !binary-tag($dist-path --> Str) {
        my IO::Path $file = "$dist-path/BINARY_TAG".IO;
        unless $file.e {
            die "❌ Missing BINARY_TAG file at { $file }. This file must "
              ~ "contain the pinned binary release tag "
              ~ "(e.g. 'binaries-notcurses-3.0.17-r1').";
        }
        my Str $tag = $file.slurp.trim;
        die "❌ BINARY_TAG file is empty." unless $tag.chars;
        $tag;
    }

    #| Parse NOTCURSES_FORK at the dist root for the source-build pin.
    #| Returns a Map with `url` (fork repo URL) and `sha` (40-char hex
    #| commit). Lines starting with `#` and blank lines are ignored;
    #| every other line must be `key=value`. Dies if the file is missing,
    #| malformed, or the SHA is the wrong shape.
    method !notcurses-fork-pin($dist-path --> Map) {
        my IO::Path $file = "$dist-path/NOTCURSES_FORK".IO;
        unless $file.e {
            die "❌ Missing NOTCURSES_FORK file at { $file }. This file "
              ~ "must contain `url=…` and `sha=…` lines naming the "
              ~ "upstream fork and pinned commit used for source builds.";
        }
        my %pin;
        for $file.slurp.lines -> Str $line {
            my Str $trimmed = $line.trim;
            next if $trimmed eq '' || $trimmed.starts-with('#');
            unless $trimmed ~~ /^ (<-[=]>+) '=' (.+) $/ {
                die "❌ Malformed line in NOTCURSES_FORK: '$line' "
                  ~ "(expected `key=value`).";
            }
            %pin{ ~$0.trim } = ~$1.trim;
        }
        for <url sha> -> Str $k {
            unless %pin{$k}:exists && %pin{$k}.chars {
                die "❌ NOTCURSES_FORK missing required key `$k`.";
            }
        }
        unless %pin<sha> ~~ /^ <[0..9a..f]> ** 40 $/ {
            die "❌ NOTCURSES_FORK sha=… must be a 40-char lowercase hex "
              ~ "commit SHA, got '%pin<sha>'.";
        }
        %pin.Map;
    }

    method !expected-sha($dist-path, Str $artifact --> Str) {
        my IO::Path $file = "$dist-path/resources/checksums.txt".IO;
        return Str unless $file.e;
        for $file.slurp.lines -> Str $line {
            my Str $trimmed = $line.trim;
            next if $trimmed eq '' || $trimmed.starts-with('#');
            my @parts = $trimmed.words;
            next unless @parts.elems >= 2;
            return @parts[0] if @parts[1] eq $artifact;
        }
        Str;
    }

    #| Compute a file's SHA-256 hex digest, shelling out to whatever
    #| the platform actually ships. On POSIX this is a fallback chain,
    #| not a single tool — the platform matrix is:
    #|
    #|   Linux (incl. minimal containers: manylinux, EL, Alpine)
    #|     → `sha256sum` only (GNU/BusyBox coreutils; no `shasum`
    #|       binary on a stock manylinux_2_28 image).
    #|   macOS / BSD
    #|     → `shasum -a 256` only (Perl tool from the base install;
    #|       no `sha256sum` unless coreutils was brew-installed).
    #|
    #| `sha256sum` is tried first since it's the more common case in
    #| CI (Linux runners/containers); a tool that's missing, un-
    #| spawnable, exits non-zero, or produces no recognizable digest
    #| falls through to the next rather than aborting the chain. Both
    #| exhausted → Str (undefined) — the caller's checksum-mismatch
    #| report already treats that as "unknown" and rejects the
    #| prebuilt, which is the correct fail-closed behaviour.
    #|
    #| The digest is parsed as the first 64-char lowercase-hex run in
    #| the first output line, rather than assuming a fixed column
    #| layout — GNU coreutils prefixes a bare `\` fused to the hex
    #| when the input path contains a backslash (irrelevant on POSIX
    #| paths, but harmless to tolerate rather than choke on).
    method !sha256(IO::Path $file --> Str) {
        if $*DISTRO.is-win {
            my $proc = run 'certutil', '-hashfile', $file.Str, 'SHA256',
                           :out, :err;
            my $out = $proc.out.slurp(:close);
            $proc.err.slurp(:close);
            for $out.lines -> Str $line {
                my Str $t = $line.subst(/\s+/, '', :g).lc;
                return $t if $t.chars == 64 && $t ~~ /^ <[0..9a..f]>+ $/;
            }
            return Str;
        }

        for ('sha256sum', $file.Str), ('shasum', '-a', '256', $file.Str)
            -> @cmd
        {
            my $proc = try run |@cmd, :out, :err;
            next without $proc;
            my Str $out = $proc.out.slurp(:close);
            $proc.err.slurp(:close);
            next unless $proc.exitcode == 0;
            my Str $first = $out.lines.head // '';
            if $first ~~ / (<[0..9a..f]> ** 64) / {
                return ~$0;
            }
        }
        Str;
    }

    # --- Source compile path (CMake, ffmpeg, etc.) ----------------------

    #| Resolve the notcurses source tree to build from. Two paths:
    #|
    #|   1. NOTCURSES_NATIVE_VENDOR_DIR=<path> — use this local checkout
    #|      verbatim, no clone, no SHA check. Dev escape hatch for
    #|      iterating on the fork without push cycles, and the only
    #|      way to install in an airgapped environment. Caller owns
    #|      the tree's contents.
    #|
    #|   2. (default) git-fetch the URL + SHA pinned in NOTCURSES_FORK
    #|      at the dist root, into a per-SHA subdirectory of the cache.
    #|      Uses `git init` + `fetch --depth 1 origin <SHA>` (GitHub
    #|      allows fetching arbitrary reachable commits), then
    #|      `checkout FETCH_HEAD`, then verifies HEAD matches the
    #|      pinned SHA. Cached per-SHA so bumping the pin invalidates
    #|      the cache automatically.
    method !ensure-notcurses-source($dist-path --> IO::Path) {
        with %*ENV<NOTCURSES_NATIVE_VENDOR_DIR> -> Str $local {
            my IO::Path $dir = $local.IO;
            unless $dir.d && "$dir/CMakeLists.txt".IO.e {
                die "❌ NOTCURSES_NATIVE_VENDOR_DIR=$local is not a "
                  ~ "notcurses source tree (no CMakeLists.txt found).";
            }
            say "Using NOTCURSES_NATIVE_VENDOR_DIR=$local as source tree.";
            return $dir;
        }

        my %pin = self!notcurses-fork-pin($dist-path);
        my Str $sha = %pin<sha>;
        my Str $url = %pin<url>;

        my Str $cache-base-str = %*ENV<NOTCURSES_NATIVE_CACHE_DIR>
            // %*ENV<XDG_CACHE_HOME>
            // "{%*ENV<HOME> // '.'}/.cache";
        my IO::Path $src-dir =
            "$cache-base-str/Notcurses-Native-source/$sha".IO;

        if $src-dir.d && "$src-dir/CMakeLists.txt".IO.e {
            # Verify HEAD still matches the pin (defends against an
            # aborted earlier fetch that left a partial tree on disk).
            my Str $head = self!git-rev-parse-head($src-dir) // '';
            if $head eq $sha {
                say "Reusing cached notcurses source at $src-dir.";
                return $src-dir;
            }
            note "⚠️  Cached source at $src-dir has wrong HEAD "
               ~ "($head), re-cloning.";
            run 'rm', '-rf', $src-dir.Str;
        }

        $src-dir.mkdir;
        say "Fetching notcurses source from $url @ $sha...";

        my @git-steps = (
            ('git', 'init', '--quiet', $src-dir.Str),
            ('git', '-C', $src-dir.Str, 'remote', 'add', 'origin', $url),
            ('git', '-C', $src-dir.Str, '-c', 'protocol.version=2',
                'fetch', '--depth', '1', '--quiet', 'origin', $sha),
            ('git', '-C', $src-dir.Str, 'checkout', '--quiet',
                'FETCH_HEAD'),
        );
        for @git-steps -> @cmd {
            my $proc = run |@cmd, :out, :err;
            my $out = $proc.out.slurp(:close);
            my $err = $proc.err.slurp(:close);
            unless $proc.exitcode == 0 {
                run 'rm', '-rf', $src-dir.Str;
                die "❌ Failed to fetch notcurses source: "
                  ~ "{ @cmd.join(' ') }\n"
                  ~ "stdout: $out\nstderr: $err\n"
                  ~ "If you're offline or behind a firewall that blocks "
                  ~ "github.com, set NOTCURSES_NATIVE_VENDOR_DIR=/path/"
                  ~ "to/local/notcurses/clone to use a pre-staged "
                  ~ "source tree.";
            }
        }

        # Belt-and-braces: confirm HEAD matches the pinned SHA. Should
        # be tautological after a fetch-by-SHA + checkout FETCH_HEAD,
        # but cheap defense against a corrupted clone.
        my Str $head = self!git-rev-parse-head($src-dir) // '';
        unless $head eq $sha {
            die "❌ Source clone HEAD ($head) does not match pinned SHA "
              ~ "($sha). Refusing to build from unverified source.";
        }
        say "✅ Fetched notcurses source → $src-dir.";
        $src-dir;
    }

    #| `git rev-parse HEAD` in $dir. Returns the trimmed SHA on success,
    #| `Str` type object on any failure.
    method !git-rev-parse-head(IO::Path $dir --> Str) {
        my $proc = run 'git', '-C', $dir.Str, 'rev-parse', 'HEAD',
                       :out, :err;
        my Str $out = $proc.out.slurp(:close).trim;
        $proc.err.slurp(:close);
        return Str unless $proc.exitcode == 0;
        $out;
    }

    #| Build notcurses from source via CMake. Matches the
    #| per-platform build recipe used by the CI workflow. Requires
    #| cmake + git + a C toolchain + system ffmpeg / ncurses /
    #| libunistring / libdeflate dev headers (see docs/Readme.rakudoc
    #| for distro-specific install commands).
    method !compile-from-source($dist-path, IO::Path $stage) {
        self!check-toolchain;

        my IO::Path $vendor-io = self!ensure-notcurses-source($dist-path);
        my Str $vendor = $vendor-io.Str;
        my Str $build-dir = "$vendor/build";
        my Str $os = $*KERNEL.name.lc;
        my Str $ext = $os ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';

        my @cmake-args = (
            'cmake', '-B', $build-dir, '-S', $vendor,
            '-DUSE_MULTIMEDIA=ffmpeg',
            '-DBUILD_FFI_LIBRARY=ON',
            '-DUSE_CXX=OFF',
            '-DBUILD_EXECUTABLES=OFF',
            '-DUSE_PANDOC=OFF',
            '-DUSE_DOCTEST=OFF',
            '-DUSE_POC=OFF',
            '-DUSE_STATIC=OFF',
            '-DCMAKE_BUILD_TYPE=Release',
        );

        # macOS: Homebrew's ncurses isn't in default pkg-config path.
        my %env = %*ENV;
        if $os ~~ /darwin/ {
            my Str $brew-prefix = '/opt/homebrew';
            $brew-prefix = '/usr/local' unless $brew-prefix.IO.d;
            my Str $nc-pkgconfig = "$brew-prefix/opt/ncurses/lib/pkgconfig";
            if $nc-pkgconfig.IO.d {
                %env<PKG_CONFIG_PATH> =
                    "$nc-pkgconfig:{%env<PKG_CONFIG_PATH> // ''}";
            }
        }

        say "Configuring notcurses via CMake...";
        my $configure = run |@cmake-args, :out, :err, :%env;
        my $cfg-out = $configure.out.slurp(:close);
        my $cfg-err = $configure.err.slurp(:close);
        unless $configure.exitcode == 0 {
            say $cfg-out;
            say $cfg-err;
            # A core-only build is a silently degraded product: image and
            # video support vanish, Cantina's avatar flow stops working, and
            # nothing downstream can tell the difference until a user hits it
            # at runtime. Every shipped binary is expected to carry the
            # multimedia backend, so this is a hard failure by default and
            # only ever a deliberate, opted-into choice.
            unless (%*ENV<NOTCURSES_NATIVE_ALLOW_NO_MULTIMEDIA> // '') eq '1' {
                die join "\n",
                    'CMake configure failed with -DUSE_MULTIMEDIA=ffmpeg.',
                    '',
                    'This usually means the FFmpeg development headers are',
                    'missing. Install them and retry:',
                    '',
                    '  Debian/Ubuntu  apt install libavdevice-dev',
                    '  Fedora         dnf install ffmpeg-devel',
                    '  macOS          brew install ffmpeg',
                    '  MSYS2/UCRT64   pacman -S mingw-w64-ucrt-x86_64-ffmpeg',
                    '',
                    'To build without image/video support anyway, set',
                    'NOTCURSES_NATIVE_ALLOW_NO_MULTIMEDIA=1. The resulting',
                    'library cannot decode images or video.',
                    '',
                    $cfg-err;
            }
            note "⚠️  NOTCURSES_NATIVE_ALLOW_NO_MULTIMEDIA=1 — building "
               ~ "core-only (no image/video support).";
            @cmake-args[5] = '-DUSE_MULTIMEDIA=none';
            $configure = run |@cmake-args, :out, :err, :%env;
            $cfg-out = $configure.out.slurp(:close);
            $cfg-err = $configure.err.slurp(:close);
            unless $configure.exitcode == 0 {
                die "CMake configure failed:\n$cfg-err";
            }
        }

        say "Compiling notcurses...";
        my Str $ncpu = do given $os {
            when /darwin/ { qx{sysctl -n hw.ncpu}.trim }
            default {
                $*DISTRO.is-win
                    ?? (%*ENV<NUMBER_OF_PROCESSORS> // '4')
                    !! (qx{nproc 2>/dev/null}.trim || '4')
            }
        };
        my $build = run 'cmake', '--build', $build-dir, '-j', $ncpu,
                        :out, :err;
        my $build-out = $build.out.slurp(:close);
        my $build-err = $build.err.slurp(:close);
        unless $build.exitcode == 0 {
            say $build-out;
            die "CMake build failed:\n$build-err";
        }

        # The same BINARY_TAG may already hold a prebuilt install. Clear its
        # complete sibling closure only after the source build itself has
        # succeeded, immediately before staging the newly-built libraries.
        self!reset-stage($stage);

        # Stage the three libs into the XDG-style staged-libs dir.
        # Upstream naming varies per platform — recursive find-lib
        # walks the build tree and matches each library's expected
        # prefix + extension. We stage every version variant
        # (`libfoo.dylib`, `libfoo.3.dylib`, `libfoo.3.0.17.dylib` on
        # macOS) because the rewritten install-names below point to
        # the canonical `.3.dylib` variant — if that file isn't
        # present at the staged path, dyld errors with "Library not
        # loaded" at the first NativeCall.
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            my IO::Path $target = $stage.add("$lib.$ext");
            self!find-lib($build-dir.IO, $lib, $ext, $stage);
            die "❌ Could not stage $lib.$ext from build tree"
                unless $target.e;
        }

        # On macOS, rewrite each staged dylib's install-name (LC_ID_DYLIB)
        # and inter-library dependency references to absolute staged
        # paths. Without this, dyld resolves the `@rpath/libnotcurses*.dylib`
        # dependencies via the executable's RPATH chain — and on a
        # Homebrew-Raku setup (`raku` has LC_RPATH = `@executable_path/../lib`
        # which is `/opt/homebrew/lib`, where Homebrew typically installs
        # an unpatched notcurses), dyld picks Homebrew's library before
        # ours and our vendored code (including any local patches) is
        # silently shadowed. Baking the absolute paths in eliminates
        # dyld's discretion. Linux/glibc has no equivalent RPATH-vs-path
        # conflict so this is macOS-only.
        if $os ~~ /darwin/ {
            self!rewrite-macos-install-names($stage, $build-dir);
        }

        # Written last: absence means the source install never completed.
        # Prebuilt extraction starts with !reset-stage, clearing this marker.
        self!mark-source-build($stage);
    }

    #| For each staged real dylib (version aliases are symlinks staged by
    #| `!find-lib` and are skipped — rewriting through them would just
    #| re-edit the same real file), set its install-name to the absolute
    #| staged path and rewrite every `@rpath/libnotcurses*.dylib`
    #| dependency reference to the matching absolute staged path. Runs
    #| `install_name_tool` once per file — no-ops for entries that don't
    #| match the rewrite pattern. macOS-only.
    method !rewrite-macos-install-names(IO::Path $stage, Str $build-dir) {
        # Variant filenames the staging step produced (find-lib copies
        # each version-suffixed dylib it can locate in the build tree,
        # so we may have e.g. libnotcurses-core.dylib +
        # libnotcurses-core.3.dylib + libnotcurses-core.3.0.17.dylib).
        #
        # Pick up every notcurses core dylib (`libnotcurses.dylib`,
        # `libnotcurses-core.3.dylib`, `libnotcurses-ffi.3.0.17.dylib`,
        # etc.) AND exclude `libnotcurses_native_shim.dylib`.
        # !try-compile-shim stages the shim with a short
        # `@loader_path/libnotcurses_native_shim.dylib` install-name;
        # its only LC_LOAD_DYLIB entries are libSystem and friends —
        # no `@rpath/libnotcurses*.dylib` references to rewrite,
        # because the shim is compiled `-undefined dynamic_lookup`
        # and resolves its notcurses calls at runtime against the
        # host process. Rewriting its install-name to the absolute
        # staged path would fail with "larger updated load commands
        # do not fit" — the shim's Mach-O headerpad is sized for
        # the short name, not the ~100-char absolute. On a force-
        # install, the previous run's shim is still on disk; this
        # pass would loudly refuse it.
        my @all-files = $stage.dir.grep({
            .basename ~~ /^ 'libnotcurses' \S* '.dylib' $ /
            && .basename !~~ /'_shim'/
            && !.l      # aliases are symlinks; the real file is enough
        });

        # Make sure files are writable; CMake sometimes installs 0444.
        for @all-files -> $f {
            $f.chmod(0o644);
        }

        # The 3-component install-name is what other libs declare as
        # their dependency (`@rpath/libnotcurses-core.3.dylib`), so this
        # is the path we want every staged variant to advertise.
        my %canonical-id =
            'libnotcurses'      => $stage.add('libnotcurses.3.dylib').absolute,
            'libnotcurses-core' => $stage.add('libnotcurses-core.3.dylib').absolute,
            'libnotcurses-ffi'  => $stage.add('libnotcurses-ffi.3.dylib').absolute,
        ;

        # Map each `@rpath/...` reference to its canonical absolute
        # staged path.
        my %dep-rewrite =
            '@rpath/libnotcurses.3.dylib'      => %canonical-id<libnotcurses>,
            '@rpath/libnotcurses-core.3.dylib' => %canonical-id<libnotcurses-core>,
            '@rpath/libnotcurses-ffi.3.dylib'  => %canonical-id<libnotcurses-ffi>,
        ;

        for @all-files -> $f {
            # Set this file's own install-name. Match by basename
            # prefix so every variant of the same logical library
            # (`.dylib`, `.3.dylib`, `.3.0.17.dylib`) gets the same
            # canonical ID.
            my Str $base = do given $f.basename {
                when /^ 'libnotcurses-core' / { 'libnotcurses-core' }
                when /^ 'libnotcurses-ffi'  / { 'libnotcurses-ffi'  }
                default                       { 'libnotcurses'      }
            };
            my Str $new-id = %canonical-id{$base};
            my $rc = run 'install_name_tool', '-id', $new-id, $f.absolute,
                         :out, :err;
            $rc.out.slurp(:close);
            my $err = $rc.err.slurp(:close);
            die "install_name_tool -id failed on {$f.basename}:\n$err"
                unless $rc.exitcode == 0;

            # Rewrite every `@rpath/libnotcurses*.dylib` dep to its
            # absolute staged path. Skip silently when the dep isn't
            # present (install_name_tool errors loudly on no-match,
            # which is fine for the libs that *do* declare it).
            for %dep-rewrite.kv -> $old, $new {
                my $rc2 = run 'install_name_tool', '-change', $old, $new,
                              $f.absolute, :out, :err;
                $rc2.out.slurp(:close);
                $rc2.err.slurp(:close);
            }
        }

        say "  Rewrote macOS install-names to absolute staged paths "
          ~ "({+@all-files} files)";
    }

    method !find-lib(IO::Path $dir, Str $lib, Str $ext, IO::Path $stage) {
        # Stage the real file(s), then recreate the version aliases as
        # RELATIVE SYMLINKS — never as extra copies. A copied-out alias
        # is a separate inode, and macOS dyld deduplicates loaded
        # images by real path, not by install-name: NativeCall's
        # dlopen of `libnotcurses-core.dylib` and the full lib's
        # LC_LOAD_DYLIB of `libnotcurses-core.3.dylib` then load TWO
        # images of the core library. Heap state (tinfo) is shared
        # between them, but per-image globals are not — most fatally
        # `notcurses_blitters`, whose NCBLIT_PIXEL entry is patched by
        # set_pixel_blitter() during terminal setup in one image while
        # the image actually blitting still holds NULL → jump-to-zero
        # segfault on the first pixel blit. One real file plus
        # symlinks keeps every path the same image (exactly the layout
        # the prebuilt archives ship). Linux ld.so dedupes by SONAME
        # so it never hit this, but gets the same layout for hygiene.
        my %links;      # alias basename => real-file basename
        self!find-lib-walk($dir, $lib, $ext, $stage, %links);
        for %links.kv -> Str $alias, Str $target {
            my IO::Path $dest = $stage.add($alias);
            # A real file already staged under this name wins (e.g. a
            # build tree that produced no symlinks in the first place).
            next if $dest.e && !$dest.l;
            next unless $stage.add($target).e;
            try $dest.unlink;
            # Raku's &symlink absolutizes its target, but the alias
            # must stay relative so the staged dir remains relocatable.
            my $ln = run 'ln', '-sfn', $target, $dest.absolute, :out, :err;
            $ln.out.slurp(:close);
            my Str $ln-err = $ln.err.slurp(:close);
            die "❌ Could not symlink $alias -> $target in $stage:\n$ln-err"
                unless $ln.exitcode == 0;
            say "  Staged: $alias -> $target (symlink)";
        }
    }

    method !find-lib-walk(IO::Path $dir, Str $lib, Str $ext,
                          IO::Path $stage, %links) {
        # Each platform names the produced library differently:
        #   Linux:   libnotcurses-core.so[.3[.0.17]]
        #   macOS:   libnotcurses-core[.3[.0.17]].dylib
        #   MinGW:   libnotcurses-core[-3].dll  or notcurses-core.dll
        #
        # IMPORTANT: `libnotcurses` is a prefix of `libnotcurses-core`
        # and `libnotcurses-ffi`. Only match separator `.` after the
        # name, never `-`, so `libnotcurses` doesn't claim
        # `libnotcurses-ffi.so`.
        #
        # Visits every matching variant rather than stopping at the
        # first hit. macOS dyld follows version suffixes in
        # install-names (e.g., `libnotcurses-core.3.dylib`) at load
        # time, so every name must be present at the staged location —
        # real files are copied here, symlink aliases are collected
        # into %links for !find-lib to recreate as symlinks.
        my Str $nolib = $lib.subst(/^ 'lib'/, '');
        my @patterns = ($lib, $nolib);

        for $dir.dir -> IO::Path $entry {
            if $entry.d {
                self!find-lib-walk($entry, $lib, $ext, $stage, %links);
                next;
            }
            next unless $entry.f;
            my Str $name = $entry.basename;
            for @patterns -> Str $pat {
                # contains(".$ext"), not ends-with: Linux reals carry the
                # version AFTER the extension (libnotcurses-core.so.3.0.17),
                # macOS before it (libnotcurses-core.3.dylib). An ends-with
                # match misses the Linux reals, and with aliases now staged
                # as symlinks (not dereferencing copies) that would leave a
                # Linux source-build stage empty: every alias would point at
                # a target that was never staged, and the target-exists
                # guard below would silently drop it. Same discipline as the
                # runtime resolver's _find-in.
                if $name eq "$pat.$ext"
                   || ($name.starts-with("$pat.") && $name.contains(".$ext")) {
                    if $entry.l {
                        # One-level-flattened: alias points straight at
                        # the fully-resolved real file's basename, like
                        # a `make install` tree.
                        %links{$name} //= $entry.resolve.basename;
                        last;
                    }
                    my IO::Path $dest = $stage.add($name);
                    # Skip if we already staged a copy this run (the
                    # build tree may surface the same file at multiple
                    # paths; first wins).
                    next if $dest.e && !$dest.l && $dest.s == $entry.s;
                    try $dest.unlink;
                    copy $entry, $dest;
                    say "  Staged: {$dest.basename} (from $name)";
                    last;
                }
            }
        }
    }

    method !check-toolchain() {
        my $git-rc = run 'git', '--version', :out, :err;
        $git-rc.out.slurp(:close);
        $git-rc.err.slurp(:close);
        unless $git-rc.exitcode == 0 {
            die "❌ git not found in PATH. The source-build fallback "
              ~ "fetches notcurses fresh from the pinned fork at build "
              ~ "time. To skip the fetch (airgapped install or local "
              ~ "fork iteration), set NOTCURSES_NATIVE_VENDOR_DIR=/path/"
              ~ "to/notcurses/source.";
        }

        my $rc = run 'cmake', '--version', :out, :err;
        $rc.out.slurp(:close);
        $rc.err.slurp(:close);
        unless $rc.exitcode == 0 {
            die q:to/ERR/;
                ❌ cmake not found in PATH.
                Install cmake + notcurses build deps. Per-distro:
                    macOS:         brew install cmake pkg-config ffmpeg ncurses \
                                       libunistring libdeflate
                    Debian/Ubuntu: sudo apt install cmake pkg-config \
                                       libncurses-dev libunistring-dev libdeflate-dev \
                                       libavformat-dev libavcodec-dev libavdevice-dev \
                                       libavutil-dev libswscale-dev
                    Fedora:        sudo dnf install cmake pkgconf-pkg-config \
                                       ncurses-devel libunistring-devel libdeflate-devel \
                                       ffmpeg-devel
                    Arch:          sudo pacman -S cmake pkgconf base-devel \
                                       ncurses libunistring libdeflate ffmpeg
                    openSUSE:      sudo zypper in cmake pkg-config gcc \
                                       ncurses-devel libunistring-devel libdeflate-devel \
                                       ffmpeg-7-libavcodec-devel ffmpeg-7-libavformat-devel \
                                       ffmpeg-7-libavutil-devel ffmpeg-7-libavdevice-devel \
                                       ffmpeg-7-libswscale-devel
                    Windows:       MSYS2 UCRT64 + mingw-w64-ucrt-x86_64-cmake / \
                                       ffmpeg / libdeflate / libunistring / ncurses / toolchain
                ERR
        }
    }

    # --- Shared helpers -------------------------------------------------

    #| Look up the prebuilt-archive slug for the current platform. Returns
    #| the slug string when the key is in %PLATFORM-SLUGS, otherwise an
    #| undefined `Str` type object (NOT `Any`) so callers can use
    #| `without $plat { ... }` to fall through to the source build.
    #|
    #| `:os` / `:hardware` / `:libc` default to live system probes
    #| (`$*KERNEL.name.lc`, `$*KERNEL.hardware.lc`, `detect-libc`) so
    #| production callers pass nothing; tests inject pairs directly to
    #| avoid having to override `$*KERNEL` or touch the filesystem.
    method detect-platform(
        Str :$os       = $*KERNEL.name.lc,
        Str :$hardware = $*KERNEL.hardware.lc,
        Str :$libc     = self.detect-libc(:$os),
        --> Str
    ) {
        %PLATFORM-SLUGS{self.detect-platform-key(:$os, :$hardware, :$libc)} // Str
    }

    #| The exact key `detect-platform` looked up — surfaced so the
    #| unknown-platform diagnostic can quote it verbatim.
    #|
    #| Linux keys carry a libc suffix (`linux-x86_64-glibc`,
    #| `linux-aarch64-musl`, etc.); non-Linux keys are just
    #| `os-hardware` because there's no libc axis to disambiguate.
    method detect-platform-key(
        Str :$os       = $*KERNEL.name.lc,
        Str :$hardware = $*KERNEL.hardware.lc,
        Str :$libc     = self.detect-libc(:$os),
        --> Str
    ) {
        $libc ?? "$os-$hardware-$libc" !! "$os-$hardware"
    }

    #| Sorted list of all keys in %PLATFORM-SLUGS, so the unknown-platform
    #| diagnostic can show the user which platforms ARE supported.
    method known-platform-keys(--> List) {
        %PLATFORM-SLUGS.keys.sort.List
    }

    #| Detect the system C library on Linux. Probe order:
    #|   1. musl loader presence — unambiguous if a `ld-musl-*.so.1`
    #|      file is on disk under `/lib` or `/usr/lib`.
    #|   2. glibc via `!detect-glibc-version`.
    #|
    #| Returns Str (undefined) for non-Linux OSes — callers strip the
    #| libc axis from the platform key on those. Also returns Str for
    #| Linux systems with neither glibc nor musl loaders visible (e.g.
    #| uclibc, statically-linked busybox systems), which the slug-map
    #| won't have a key for, so they fall through to source build.
    method detect-libc(Str :$os = $*KERNEL.name.lc --> Str) {
        return Str unless $os eq 'linux';
        for </lib /usr/lib> -> Str $d {
            next unless $d.IO.d;
            return 'musl' if try {
                $d.IO.dir.first(*.basename.starts-with('ld-musl-'))
            };
        }
        return 'glibc' if self!detect-glibc-version.defined;
        Str
    }

    #| Parse `ldd --version` for the system's glibc version. Returns a
    #| Version on glibc systems, undefined Version on musl (ldd --version
    #| exits non-zero) or when ldd is absent / unparseable. Only
    #| meaningful on Linux — don't call on other OSes.
    method !detect-glibc-version(--> Version) {
        my $proc = try { run 'ldd', '--version', :out, :err };
        return Version without $proc;
        my $out = $proc.out.slurp(:close);
        $proc.err.slurp(:close);
        return Version unless $proc.exitcode == 0;
        my $first = $out.lines.head // '';
        if $first ~~ / (\d+ '.' \d+ [ '.' \d+ ]?) \s* $ / {
            return Version.new(~$0);
        }
        Version;
    }

    #|( Compile the perf shim alongside the staged libnotcurses libs.
        See src/notcurses_native_shim.c for what it contains and why
        — short version: a couple of hot loops (currently just the
        per-cell plane copy used by Selkie::Widget::ViewportedCardList)
        that are unaffordable to express call-per-cell over the Raku
        NativeCall boundary.

        Linked with -undefined dynamic_lookup (macOS) or
        -Wl,--unresolved-symbols=ignore-in-shared-libs (Linux) so the
        shim doesn't need libnotcurses at link time. The notcurses
        symbols it calls resolve at runtime via the host process's
        already-loaded libnotcurses (which Notcurses::Native loaded
        via NativeCall before the shim is ever invoked).

        EXPECTED CI BEHAVIOUR: the prebuilt release archives should
        ship libnotcurses_native_shim.{dylib,so,dll} pre-compiled
        alongside the libnotcurses libs, plus a sidecar
        libnotcurses_native_shim.<ext>.srchash holding the SHA-256
        (hex) of the src/notcurses_native_shim.c it was compiled
        from. The CI lanes that produce those archives
        (.github/workflows/_build-{macos,windows}.yml and
        scripts/ci/build-linux-{glibc,musl}.sh) compile
        src/notcurses_native_shim.c with the same flags this
        method uses and write the sidecar next to it. When the
        staged sidecar matches the shim source
        this dist ships, this method short-circuits — so users
        installing a prebuilt never hit the compile path and
        don't need a C toolchain. The freshness check is
        content-based on purpose: mtimes are meaningless across
        machines. A dist tarball is packaged after the binary
        pack is built, so on every fresh ecosystem install the
        extracted source looked "newer than" the archive's shim
        and silently forced the compile path — observed
        2026-08-11 on a toolchain-less Alpine CI container, where
        it surfaced as the per-cell-fallback warning despite the
        musl pack shipping a perfectly good shim. Packs that
        predate the sidecar fall back to the old mtime
        comparison. Every successful local compile writes the
        sidecar and parks a content-addressed copy of the shim
        under <cache>/shims/<src-sha256>.<ext>, so a
        toolchain-equipped machine compiles at most once per
        (shim source, binary tag) even though !extract-archive
        wipes the stage dir on every install.

        FALLBACK: when a prebuilt is unavailable (unknown platform
        / source-build path), or when this Build.rakumod is shipping
        a newer src/notcurses_native_shim.c than the prebuilt
        archive contains, we compile here at install time. Non-fatal
        if no C compiler is available — Selkie's bindings fall back
        to a per-cell Raku merge (the pre-shim behaviour). The
        warning explains the perf cost so the user notices. )
    method !try-compile-shim($dist-path, IO::Path $stage --> Nil) {
        my Str $os = $*KERNEL.name.lc;
        my Str $ext = $os ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';
        my IO::Path $shim = $stage.add("libnotcurses_native_shim.$ext");
        my IO::Path $sidecar = $stage.add("libnotcurses_native_shim.$ext.srchash");
        my Str $src = "$dist-path/src/notcurses_native_shim.c";

        return unless $src.IO.e;

        my Str $src-hash = (try self!sha256($src.IO)) // Str;

        # Skip rebuild when the staged shim was built from the same
        # shim source this dist ships, per the .srchash sidecar (see
        # method doc). Mirror Vips-Native's same-named method. The
        # mtime branch only serves packs that predate the sidecar
        # (and systems where hashing itself failed).
        if $shim.e {
            if $sidecar.e && $src-hash.defined {
                my Str $packed = (try $sidecar.slurp.trim) // '';
                return if $packed eq $src-hash;
                say "🔁 Staged shim was built from different source — refreshing.";
            }
            else {
                my $src-mtime  = $src.IO.modified // 0;
                my $shim-mtime = $shim.modified  // 0;
                return if $shim-mtime >= $src-mtime;
                say "🔁 Source newer than staged shim — refreshing.";
            }
        }

        $stage.mkdir;

        # Content-addressed local build cache: every successful compile
        # below also lands in <cache>/shims/<src-sha256>.<ext> (the
        # cache dir is already keyed by BINARY_TAG). !extract-archive
        # wipes the stage on every install, so a stamped sidecar alone
        # cannot survive a reinstall — restoring from here means a
        # machine that compiled once skips the git header fetch and
        # the C toolchain requirement on every subsequent install.
        # Keyed by content, so a shim-source edit can never hit a
        # stale entry. Safe to relocate: the shim is built with a
        # relative install-name / $ORIGIN rpath on every platform.
        my IO::Path $shim-cache =
            self!cache-dir(self!binary-tag($dist-path)).add('shims');
        if $src-hash.defined {
            my IO::Path $cached-shim = $shim-cache.add("$src-hash.$ext");
            if $cached-shim.e {
                $cached-shim.copy($shim);
                $shim.chmod(0o755);
                $sidecar.spurt("$src-hash\n");
                say "✅ Restored Notcurses perf shim from build cache → $shim.";
                return;
            }
        }

        # The notcurses headers + (Windows) import lib live in the
        # source tree resolved by !ensure-notcurses-source: either
        # NOTCURSES_NATIVE_VENDOR_DIR, or the per-SHA git-fetch cache
        # under $NOTCURSES_NATIVE_CACHE_DIR / XDG_CACHE_HOME. Fetch is
        # lazy — only happens when we actually need to (re)compile,
        # so prebuilt-with-shim installs (the 99% case) never hit git.
        # Non-fatal on fetch failure: the perf cost falls back to
        # Selkie's Raku per-cell merge with a one-shot warning, same
        # as a missing C toolchain below.
        my IO::Path $nc-src;
        my $fetch-error;
        {
            CATCH {
                default {
                    $fetch-error = .message;
                }
            }
            $nc-src = self!ensure-notcurses-source($dist-path);
        }
        if $fetch-error {
            note "⚠️  Skipping shim compile — couldn't resolve notcurses "
               ~ "source for include headers: $fetch-error";
            note "    Set NOTCURSES_NATIVE_VENDOR_DIR=<path> to point at "
               ~ "a local checkout, or ensure git is available so the "
               ~ "pinned SHA can be fetched.";
            return;
        }
        my Str $inc = "{$nc-src}/include";

        # Windows needs an import lib to satisfy link-time symbol
        # resolution (no equivalent of -undefined dynamic_lookup).
        # Look for one in the source-build dir — present when the
        # current install came via compile-from-source (CMake produces
        # libnotcurses-core.dll.a alongside the DLL). Prebuilt-only
        # installs don't ship the import lib, so we can't compile
        # here; the shim has to come from CI via the prebuilt archive.
        # In that fallback case Selkie's binding fails to load and
        # !merge-widget-plane uses its Raku-side fallback path.
        my $import-lib;
        if $*DISTRO.is-win {
            my $build-dir = "{$nc-src}/build";
            with $build-dir.IO.&{ .e ?? .dir(test => /'libnotcurses-core.dll.a'$/) !! () }.first {
                $import-lib = .Str;
            }
            without $import-lib {
                note "⚠️  Skipping Windows shim compile — no "
                   ~ "libnotcurses-core.dll.a in $build-dir "
                   ~ "(only present after a from-source build). The "
                   ~ "shim normally ships pre-compiled in the prebuilt "
                   ~ "archive; if the prebuilt didn't include it, "
                   ~ "Selkie's ViewportedCardList falls back to a "
                   ~ "Raku per-cell merge (correct, slower).";
                return;
            }
        }

        my @cmd = do given $os {
            when /darwin/ {
                # -headerpad_max_install_names: reserve generous load-
                # command padding so any future install_name_tool -id
                # call (e.g. moving the shim to an absolute staged
                # path) doesn't fail with "larger updated load
                # commands do not fit". Note: !rewrite-macos-install-
                # names explicitly skips the shim today — this is
                # belt-and-braces for future relocators.
                'cc', '-O2', '-dynamiclib', '-fPIC',
                '-Wl,-headerpad_max_install_names',
                '-install_name', "\@loader_path/libnotcurses_native_shim.dylib",
                '-undefined', 'dynamic_lookup',
                "-I$inc",
                '-o', $shim.Str, $src;
            }
            when /win/ {
                # Link against the import lib found above. Windows DLL
                # search at runtime finds libnotcurses-core.dll as a
                # sibling in the same staged dir.
                'cc', '-O2', '-shared',
                "-I$inc",
                '-o', $shim.Str, $src,
                $import-lib;
            }
            default {
                # Linux: explicit link against the staged
                # libnotcurses-core, RPATH '$ORIGIN' so at runtime
                # the shim resolves its NEEDED entry to its own
                # sibling (our patched libnotcurses-core.so).
                # Mirror Vips-Native's shim-build pattern. An
                # earlier version used `-Wl,--unresolved-symbols=
                # ignore-in-shared-libs` to defer to runtime; that
                # flag only suppresses errors from shared-lib deps
                # we link against, not from our own object file's
                # undefined references to notcurses symbols — so
                # ld correctly rejected the link.
                'cc', '-O2', '-shared', '-fPIC',
                "-I$inc",
                "-L$stage", '-lnotcurses-core',
                '-Wl,-soname,libnotcurses_native_shim.so',
                "-Wl,-rpath,\$ORIGIN",
                '-o', $shim.Str, $src;
            }
        };

        my $rc = run |@cmd, :out, :err;
        my $err = $rc.err.slurp(:close);
        $rc.out.slurp(:close);
        if $rc.exitcode == 0 {
            say "✅ Compiled Notcurses perf shim → $shim.";
            # Stamp what we compiled (content match beats cross-machine
            # mtime guesses) and park a copy in the build cache so the
            # next install's wiped stage can restore instead of
            # recompiling.
            if $src-hash.defined {
                try $sidecar.spurt("$src-hash\n");
                try {
                    $shim-cache.mkdir;
                    $shim.copy($shim-cache.add("$src-hash.$ext"));
                }
            }
        }
        else {
            note "⚠️  Could not compile Notcurses perf shim ($shim): $err";
            note "    Non-fatal — Selkie::Widget::ViewportedCardList "
               ~ "will fall back to its per-cell Raku merge loop. "
               ~ "Install a C toolchain (xcode-select --install / "
               ~ "apt install build-essential) and reinstall to get "
               ~ "the fast path.";
        }
    }

}
