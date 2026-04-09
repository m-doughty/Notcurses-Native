use NativeCall;
use Notcurses::Native::Types;

unit module TestHelper;

# Redirect stdout/stderr to /dev/null so notcurses terminal escape
# sequences don't corrupt the TAP stream. Reroute Raku's $*OUT to
# the saved stdout fd via /dev/fd/N so TAP output still works.

sub dup(int32 --> int32) is native { * }
sub dup2(int32, int32 --> int32) is native { * }
sub open_c(Str, int32 --> int32) is native is symbol('open') { * }
sub fopen(Str, Str --> Pointer) is native is export { * }

my $null-path = $*KERNEL.name.lc ~~ /win/ ?? 'NUL' !! '/dev/null';

my int32 $saved-stdout = dup(1);
my int32 $null-fd = open_c($null-path, 1);
dup2($null-fd, 1);
dup2($null-fd, 2);

# Reroute $*OUT to saved fd
if "/dev/fd/$saved-stdout".IO.e {
	$*OUT = open("/dev/fd/$saved-stdout", :w);
} elsif $*KERNEL.name.lc ~~ /win/ {
	# Windows: restore fd 1 for TAP — notcurses on Windows uses ConPTY
	# which doesn't leak escapes the same way
	dup2($saved-stdout, 1);
} else {
	# Linux fallback: /proc/self/fd/N
	$*OUT = open("/proc/self/fd/$saved-stdout", :w);
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
