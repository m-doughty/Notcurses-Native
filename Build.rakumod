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
                return True;
            }
        }

        unless $force-source {
            if self!try-prebuilt($dist-path, $plat, $binary-tag, $stage) {
                say "✅ Installed prebuilt Notcurses binaries ($plat) for "
                  ~ "$binary-tag → $stage.";
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
        True;
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
            @cmake-args[3] = '-DUSE_MULTIMEDIA=none';
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
        # prefix + extension.
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            my IO::Path $target = $stage.add("$lib.$ext");
            self!find-lib($build-dir.IO, $lib, $ext, $target);
            die "❌ Could not stage $lib.$ext from build tree"
                unless $target.e;
        }
    }

    method !find-lib(IO::Path $dir, Str $lib, Str $ext, IO::Path $target) {
        # Each platform names the produced library differently:
        #   Linux:   libnotcurses-core.so[.3[.0.17]]
        #   macOS:   libnotcurses-core[.3[.0.17]].dylib
        #   MinGW:   libnotcurses-core[-3].dll  or notcurses-core.dll
        #
        # IMPORTANT: `libnotcurses` is a prefix of `libnotcurses-core`
        # and `libnotcurses-ffi`. Only match separator `.` after the
        # name, never `-`, so `libnotcurses` doesn't claim
        # `libnotcurses-ffi.so`.
        my Str $nolib = $lib.subst(/^ 'lib'/, '');
        my @patterns = ($lib, $nolib);

        for $dir.dir -> IO::Path $entry {
            if $entry.d {
                self!find-lib($entry, $lib, $ext, $target);
                return if $target.e;
            }
            next unless $entry.f;
            my Str $name = $entry.basename;
            for @patterns -> Str $pat {
                if $name eq "$pat.$ext"
                   || $name ~~ /^ $pat '.' .* $ext $/ {
                    copy $entry, $target;
                    say "  Staged: {$target.basename} (from $name)";
                    return;
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

}
