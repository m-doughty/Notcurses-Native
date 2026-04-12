class Build {
	method build($dist-path) {
		self!check-dependencies;

		my $vendor = "$dist-path/vendor/notcurses";
		my $build-dir = "$vendor/build";
		my $resources = "$dist-path/resources/lib";

		$resources.IO.mkdir;

		say "Building notcurses 3.0.17 from vendored source...";

		my $os = $*KERNEL.name.lc;
		my $ext = $os ~~ /darwin/ ?? 'dylib' !! $os ~~ /win/ ?? 'dll' !! 'so';

		# Configure
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

		# macOS: homebrew ncurses isn't in default pkg-config path
		my %env = %*ENV;
		if $os ~~ /darwin/ {
			my $brew-prefix = '/opt/homebrew';
			$brew-prefix = '/usr/local' unless $brew-prefix.IO.d;
			my $nc-pkgconfig = "$brew-prefix/opt/ncurses/lib/pkgconfig";
			if $nc-pkgconfig.IO.d {
				%env<PKG_CONFIG_PATH> = "$nc-pkgconfig:{%env<PKG_CONFIG_PATH> // ''}";
			}
		}

		say "Configuring...";
		my $configure = run |@cmake-args, :out, :err, :%env;
		my $cfg-out = $configure.out.slurp(:close);
		my $cfg-err = $configure.err.slurp(:close);
		unless $configure.exitcode == 0 {
			say $cfg-out;
			say $cfg-err;

			# Try fallback without ffmpeg
			say "FFmpeg not found, trying core-only build...";
			@cmake-args[3] = '-DUSE_MULTIMEDIA=none';
			$configure = run |@cmake-args, :out, :err, :%env;
			$cfg-out = $configure.out.slurp(:close);
			$cfg-err = $configure.err.slurp(:close);
			die "CMake configure failed:\n$cfg-err" unless $configure.exitcode == 0;
		}

		# Build
		say "Compiling...";
		my $ncpu = do given $os {
			when /darwin/ { qx{sysctl -n hw.ncpu}.trim }
			when /win/    { %*ENV<NUMBER_OF_PROCESSORS> // '4' }
			default       { qx{nproc}.trim || '4' }
		};
		my $build = run 'cmake', '--build', $build-dir, '-j', $ncpu,
			:out, :err;
		my $build-out = $build.out.slurp(:close);
		my $build-err = $build.err.slurp(:close);
		unless $build.exitcode == 0 {
			say $build-out;
			die "CMake build failed:\n$build-err";
		}

		# Stage libraries
		say "Staging libraries...";
		for <libnotcurses libnotcurses-core libnotcurses-ffi> -> $lib {
			# Search recursively — CMake may put libs in subdirectories
			my $target = "$resources/$lib.$ext".IO;
			my $found = False;
			self!find-lib($build-dir.IO, $lib, $ext, $target);
		}

		# Create empty stubs for other platforms
		for <dylib so dll> -> $other-ext {
			next if $other-ext eq $ext;
			for <libnotcurses libnotcurses-core libnotcurses-ffi> -> $lib {
				my $stub = "$resources/$lib.$other-ext".IO;
				$stub.spurt("") unless $stub.e;
			}
		}

		say "Build complete.";
		True;
	}

	method !find-lib(IO::Path $dir, Str $lib, Str $ext, IO::Path $target) {
		# Search for the library in build output, handling platform naming differences
		# MinGW: libnotcurses-core.dll or libnotcurses-core-3.dll
		# MSVC: notcurses-core.dll
		# Linux: libnotcurses-core.so or libnotcurses-core.so.3.0.17
		# macOS: libnotcurses-core.dylib or libnotcurses-core.3.dylib
		my $nolib = $lib.subst(/^ 'lib'/, '');
		my @patterns = ($lib, $nolib);

		for $dir.dir -> $entry {
			if $entry.d {
				# Recurse into subdirectories
				self!find-lib($entry, $lib, $ext, $target);
				return if $target.e;
			}
			next unless $entry.f;
			my $name = $entry.basename;
			for @patterns -> $pat {
				if $name ~~ /^ $pat [ '.' | '-' ] .* $ext $/ || $name eq "$pat.$ext" {
					copy $entry, $target;
					say "  Staged: {$target.basename} (from $name)";
					return;
				}
			}
		}
	}

	method !check-dependencies {
		for <cmake> -> $bin {
			next if self!find-bin($bin);
			die "Required tool '$bin' not found. Please install it.";
		}
	}

	method !find-bin(Str $bin --> Bool) {
		# Check PATH first
		my $which = $*KERNEL.name.lc ~~ /win/ ?? 'where' !! 'which';
		my $check = run $which, $bin, :out, :err;
		return True if $check.exitcode == 0;

		# Search common locations (subprocess may have a stripped PATH)
		my @paths = $*KERNEL.name.lc ~~ /darwin/
			?? </opt/homebrew/bin /usr/local/bin /usr/bin>
			!! </usr/bin /usr/local/bin /snap/bin>;
		for @paths -> $dir {
			my $full = "$dir/$bin".IO;
			if $full.e && $full.x {
				# Add to PATH for subsequent commands
				%*ENV<PATH> = "$dir:{%*ENV<PATH> // ''}";
				say "  Found $bin at $full";
				return True;
			}
		}
		False;
	}
}
