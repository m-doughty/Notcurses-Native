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
#| Env-var knobs:
#|
#|   NOTCURSES_NATIVE_BUILD_FROM_SOURCE=1  skip prebuilt, always compile
#|   NOTCURSES_NATIVE_BINARY_ONLY=1        refuse to fall back to compile
#|   NOTCURSES_NATIVE_BINARY_URL=<url>     override GH release base URL
#|   NOTCURSES_NATIVE_CACHE_DIR=<path>     override cache directory
#|   NOTCURSES_NATIVE_LIB_DIR=<path>       (runtime) load libs from this
#|                                         dir instead of %?RESOURCES

class Build {

    # --- Constants ------------------------------------------------------

    constant $DEFAULT-BASE-URL =
        'https://github.com/m-doughty/Notcurses-Native/releases/download';

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

        without $plat {
            note "⚠️  Unknown platform ({$*KERNEL.name}-{$*KERNEL.hardware}); "
                ~ "falling back to source build.";
            self!compile-from-source($dist-path);
            self!stage-stubs($dist-path);
            return True;
        }

        unless $force-source {
            if self!try-prebuilt($dist-path, $plat, $binary-tag) {
                self!stage-stubs($dist-path);
                say "✅ Installed prebuilt Notcurses binaries ($plat) for $binary-tag.";
                return True;
            }
            if $binary-only {
                die "NOTCURSES_NATIVE_BINARY_ONLY=1 set but prebuilt download "
                  ~ "failed for $plat ($binary-tag).";
            }
            note "⚠️  Prebuilt archive unavailable for $plat ($binary-tag) "
               ~ "— compiling from source via CMake.";
        }

        self!compile-from-source($dist-path);
        self!stage-stubs($dist-path);
        say "✅ Compiled Notcurses from vendored source.";
        True;
    }

    # --- Prebuilt binary path -------------------------------------------

    method !try-prebuilt($dist-path, Str $plat, Str $binary-tag --> Bool) {
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

        self!extract-archive($cached, $dist-path);
        True;
    }

    method !artifact-name(Str $plat --> Str) {
        my Str $archive-ext = $plat.starts-with('windows') ?? 'zip' !! 'tar.gz';
        "notcurses-$plat.$archive-ext";
    }

    method !extract-archive(IO::Path $archive, $dist-path) {
        my IO::Path $dest = "$dist-path/resources/lib".IO;
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
        my Str $ext = $*KERNEL.name.lc ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            my IO::Path $f = $dest.add("$lib.$ext");
            die "❌ Prebuilt archive missing expected lib: $lib.$ext"
                unless $f.e;
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
    method !compile-from-source($dist-path) {
        self!check-toolchain;

        my Str $vendor = "$dist-path/vendor/notcurses";
        my Str $build-dir = "$vendor/build";
        my Str $resources = "$dist-path/resources/lib";
        my Str $os = $*KERNEL.name.lc;
        my Str $ext = $os ~~ /darwin/ ?? 'dylib'
                   !! $*DISTRO.is-win ?? 'dll'
                   !! 'so';

        $resources.IO.mkdir;

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

        # Stage the three libs. Upstream naming varies — recursive
        # find-lib walks the build tree and matches each library's
        # expected prefix + extension.
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            my IO::Path $target = "$resources/$lib.$ext".IO;
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

    #| Empty placeholders for non-target platforms so META6.json's
    #| resources list stays satisfiable. We have three libs × three
    #| extensions = nine potential files; whichever extension matches
    #| this platform gets real content, the other six get zero-byte
    #| stubs.
    method !stage-stubs($dist-path) {
        my Str $resources = "$dist-path/resources/lib";
        for <libnotcurses libnotcurses-core libnotcurses-ffi> -> Str $lib {
            for <dylib so dll> -> Str $ext {
                my IO::Path $path = "$resources/$lib.$ext".IO;
                $path.spurt('') unless $path.e;
            }
        }
    }
}
