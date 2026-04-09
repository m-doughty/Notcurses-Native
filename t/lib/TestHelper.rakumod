use NativeCall;
use Notcurses::Native::Types;

unit module TestHelper;

# Redirect stdout/stderr to /dev/null so notcurses terminal escape
# sequences don't corrupt the TAP stream. Reroute Raku's $*OUT to
# the saved stdout fd so TAP output still works.

sub dup(int32 --> int32) is native { * }
sub dup2(int32, int32 --> int32) is native { * }
sub open_c(Str, int32 --> int32) is native is symbol('open') { * }
sub fopen(Str, Str --> Pointer) is native is export { * }

my $null-path = $*KERNEL.name.lc ~~ /win/ ?? 'NUL' !! '/dev/null';

my int32 $saved-stdout = dup(1);
my int32 $null-fd = open_c($null-path, 1);
dup2($null-fd, 1);
dup2($null-fd, 2);

# Reroute $*OUT to saved fd via fd-backed path
my Bool $rerouted = False;
for "/dev/fd/$saved-stdout", "/proc/self/fd/$saved-stdout" -> $path {
	if $path.IO.e {
		try {
			$*OUT = open($path, :w);
			$rerouted = True;
			last;
		}
	}
}

# Last resort: restore fd 1 directly. Notcurses escape sequences may
# leak on some platforms, but tests will at least produce output.
unless $rerouted {
	dup2($saved-stdout, 1);
}

sub test-init-nc(NotcursesOptions $opts --> List) is export {
	my $devnull = fopen($null-path, 'w');

	use Notcurses::Native;
	my $nc = notcurses_init($opts, $devnull);
	($nc, $devnull)
}

sub test-init-direct( --> List) is export {
	my $devnull = fopen($null-path, 'w');

	use Notcurses::Native::Direct;
	my $ncd = ncdirect_core_init(Str, $devnull, 0);
	($ncd, $devnull)
}
