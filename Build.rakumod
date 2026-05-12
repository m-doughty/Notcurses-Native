#| Build.rakumod for Notcurses::Native.
#|
#| Two paths, tried in order:
#|
#|   1. Prebuilt binary archive download from GitHub Releases. One
#|      archive per platform contains libnotcurses, libnotcurses-core,
#|      libnotcurses-ffi, plus any ffmpeg sibling dylibs relocated to
#|      load from the same directory (@loader_path on macOS, $ORIGIN
#|      on Linux, sibling-DLL on Windows). Archive format is .tar.gz
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
#|   baked in via @loader_path / $ORIGIN / sibling-DLL load
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
#|
#| Linux prebuilts are built on ubuntu-22.04 (glibc 2.35 — see the
#| $MIN-GLIBC constant). On systems with older glibc (Ubuntu 20.04 /
#| Debian 11 / RHEL 8 / etc.) the prebuilt libnotcurses / ffmpeg libs
#| load but die at first symbol use with "GLIBC_2.xx not found".
#| Build detects this via `ldd --version` and short-circuits to the
#| CMake source build before the download even happens.

class Build {

    # --- Constants ------------------------------------------------------

    constant $DEFAULT-BASE-URL =
        'https://github.com/m-doughty/Notcurses-Native/releases/download';

    # Minimum glibc the prebuilt Linux archives are compatible with.
    # The CI workflow builds on ubuntu-22.04 (glibc 2.35); libnotcurses
    # + the sibling ffmpeg dylibs reference GLIBC_2.3x versioned
    # symbols so loading on older systems fails with "GLIBC_2.xx not
    # found". Bump in lockstep with the CI runner OS.
    constant $MIN-GLIBC = v2.35;

    # Map (OS, hardware) → platform slug used in release artefact
    # filenames + cache paths. macOS ships as arm64-only for v1 —
    # cross-compiling universal ffmpeg on an arm64-only runner fleet
    # is substantially more CI work than the other platforms. Intel
    # Mac users fall through to the compile fallback (deliberately
    # unmapped here so detect-platform returns Str, triggering the
    # unknown-platform branch in build()).
    my %PLATFORM-SLUGS =
        'darwin-arm64'    => 'macos-arm64',
        'linux-x86_64'    => 'linux-x86_64-glibc',
        'linux-aarch64'   => 'linux-aarch64-glibc',
        'win32-x86_64'    => 'windows-x86_64',
        'win32-aarch64'   => 'windows-arm64',
        'mswin32-x86_64'  => 'windows-x86_64',
        'mswin32-aarch64' => 'windows-arm64',
    ;

    # --- Entry point ----------------------------------------------------

    method build($dist-path) {
        my Bool $force-source = ?%*ENV<NOTCURSES_NATIVE_BUILD_FROM_SOURCE>;
        my Bool $binary-only  = ?%*ENV<NOTCURSES_NATIVE_BINARY_ONLY>;

        my Str $binary-tag = self!binary-tag($dist-path);
        my Str $plat = self!detect-platform;

        # Make BINARY_TAG available via %?RESOURCES so Native.rakumod
        # can find the corresponding staged-libs dir at runtime. This
        # is a tiny text file so it survives zef's resource-hashing
        # rename intact (we only ever read its contents).
        self!stage-binary-tag($dist-path);

        # Where the libs actually go. Stable XDG-style location, NOT
        # under the dist's resources/ — see header comment for why.
        my IO::Path $stage = self!staged-lib-dir($binary-tag);

        without $plat {
            note "⚠️  Unknown platform ({$*KERNEL.name}-{$*KERNEL.hardware}); "
                ~ "falling back to source build.";
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

    # --- Prebuilt binary path -------------------------------------------

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
            note "Checksum mismatch for $artifact "
                ~ "(expected $expected, got {$actual // 'unknown'}).";
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
        if $dest.d {
            for $dest.dir { .unlink if .f || .l }
        }
        $dest.mkdir;

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
        my $proc = run 'shasum', '-a', '256', $file.Str, :out, :err;
        my $out = $proc.out.slurp(:close);
        $proc.err.slurp(:close);
        $out.words.head;
    }

    # --- Source compile path (CMake, ffmpeg, etc.) ----------------------

    #| Build notcurses from the vendored source via CMake. Matches the
    #| per-platform build recipe used by the CI workflow. Requires
    #| cmake + a C toolchain + system ffmpeg / ncurses / libunistring
    #| / libdeflate dev headers (see docs/Readme.rakudoc for distro-
    #| specific install commands).
    method !compile-from-source($dist-path, IO::Path $stage) {
        self!check-toolchain;

        my Str $vendor = "$dist-path/vendor/notcurses";
        my Str $build-dir = "$vendor/build";
        my Str $os = $*KERNEL.name.lc;
        my Str $ext = $os ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';

        $stage.mkdir;

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
            # Retry without multimedia as last-resort fallback
            # (disables image/video support — Cantina's avatar flow
            # won't work, but core TUI still does).
            note "⚠️  FFmpeg not found — retrying core-only build "
               ~ "(no image/video support).";
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
    }

    #| For each staged dylib (and its version symlinks copied as real
    #| files by `!find-lib`), set its install-name to the absolute staged
    #| path and rewrite every `@rpath/libnotcurses*.dylib` dependency
    #| reference to the matching absolute staged path. Runs
    #| `install_name_tool` once per file — no-ops for entries that don't
    #| match the rewrite pattern. macOS-only.
    method !rewrite-macos-install-names(IO::Path $stage, Str $build-dir) {
        # Variant filenames the staging step produced (find-lib copies
        # each version-suffixed dylib it can locate in the build tree,
        # so we may have e.g. libnotcurses-core.dylib +
        # libnotcurses-core.3.dylib + libnotcurses-core.3.0.17.dylib).
        my @all-files = $stage.dir.grep({
            .basename ~~ /^ 'libnotcurses' \S* '.dylib' $ /
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
        # Stages every matching variant into $stage rather than
        # stopping at the first hit. macOS dyld follows version
        # suffixes in install-names (e.g., `libnotcurses-core.3.dylib`)
        # at load time, so the corresponding files must all be present
        # at the staged location.
        my Str $nolib = $lib.subst(/^ 'lib'/, '');
        my @patterns = ($lib, $nolib);

        for $dir.dir -> IO::Path $entry {
            if $entry.d {
                self!find-lib($entry, $lib, $ext, $stage);
                next;
            }
            next unless $entry.f;
            my Str $name = $entry.basename;
            for @patterns -> Str $pat {
                if $name eq "$pat.$ext"
                   || $name ~~ /^ $pat '.' .* $ext $/ {
                    my IO::Path $dest = $stage.add($name);
                    # Skip if we already staged a copy this run (the
                    # build tree may surface the same file at multiple
                    # paths via symlinks; first wins).
                    next if $dest.e && $dest.s == $entry.s;
                    copy $entry, $dest;
                    say "  Staged: {$dest.basename} (from $name)";
                    last;
                }
            }
        }
    }

    method !check-toolchain() {
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

    method !detect-platform(--> Str) {
        my Str $key = "{$*KERNEL.name.lc}-{$*KERNEL.hardware.lc}";
        %PLATFORM-SLUGS{$key};
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
        alongside the libnotcurses libs. The CI workflow that
        produces those archives (m-doughty/Notcurses-Native repo,
        not in-tree) needs a step that compiles src/notcurses_
        native_shim.c with the same flags this method uses. When
        the staged-libs dir already contains a shim at least as
        new as the source, this method short-circuits — so users
        installing a prebuilt never hit the compile path and don't
        need a C toolchain.

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
        my Str $src = "$dist-path/src/notcurses_native_shim.c";

        return unless $src.IO.e;

        # Skip rebuild when staged shim is already at least as new as
        # the source. Mirror Vips-Native's same-named method.
        if $shim.e {
            my $src-mtime  = $src.IO.modified // 0;
            my $shim-mtime = $shim.modified  // 0;
            return if $shim-mtime >= $src-mtime;
            say "🔁 Source newer than staged shim — recompiling.";
        }

        $stage.mkdir;

        my $inc = "$dist-path/vendor/notcurses/include";

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
            my $build-dir = "$dist-path/vendor/notcurses/build";
            with $build-dir.IO.&{ .e ?? .dir(test => /'libnotcurses-core.dll.a'$/) !! () }.first {
                $import-lib = .Str;
            }
            without $import-lib {
                note "⚠️  Skipping Windows shim compile — no "
                   ~ "libnotcurses-core.dll.a in vendor/notcurses/build "
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
                'cc', '-O2', '-dynamiclib', '-fPIC',
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
                # Linux: -Wl,--unresolved-symbols=ignore-in-shared-libs
                # is the GNU ld equivalent of -undefined dynamic_lookup.
                # Lets us link without naming a libnotcurses to resolve
                # against — the symbols come from the host process at
                # runtime.
                'cc', '-O2', '-shared', '-fPIC',
                "-I$inc",
                '-Wl,--unresolved-symbols=ignore-in-shared-libs',
                '-o', $shim.Str, $src;
            }
        };

        my $rc = run |@cmd, :out, :err;
        my $err = $rc.err.slurp(:close);
        $rc.out.slurp(:close);
        if $rc.exitcode == 0 {
            say "✅ Compiled Notcurses perf shim → $shim.";
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
