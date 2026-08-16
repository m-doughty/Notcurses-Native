use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native::Str;

unit module TestHelper;

# Redirect stdout/stderr to /dev/null so notcurses terminal escape
# sequences don't corrupt the TAP stream. Reroute Raku's $*OUT to
# the saved stdout fd so TAP output still works.

# A bare `is native` resolves against the running executable's symbol table.
# That finds libc on POSIX, but MoarVM.exe exports no dup/dup2/open, so every
# xt file died at compile time with "Cannot locate symbol 'dup' in native
# library ''". Name the C runtime explicitly — libc-name() is the same
# resolver Notcurses::Native::Str uses, and returns ucrtbase.dll on Windows.
# The UCRT also renames the POSIX I/O entry points with a leading underscore;
# the unprefixed spellings genuinely do not exist there.
my constant DUP-SYM   = $*DISTRO.is-win ?? '_dup'   !! 'dup';
my constant DUP2-SYM  = $*DISTRO.is-win ?? '_dup2'  !! 'dup2';
my constant OPEN-SYM  = $*DISTRO.is-win ?? '_open'  !! 'open';

sub dup(int32 --> int32) is native(&libc-name) is symbol(DUP-SYM) { * }
sub dup2(int32, int32 --> int32) is native(&libc-name) is symbol(DUP2-SYM) { * }
sub open_c(Str, int32 --> int32) is native(&libc-name) is symbol(OPEN-SYM) { * }
sub fopen(Str, Str --> Pointer) is native(&libc-name) is export { * }

my $null-path = $*KERNEL.name.lc ~~ /win/ ?? 'NUL' !! '/dev/null';

# Skipped entirely on Windows. MoarVM keeps its own private CRT descriptor
# table, and dup2()-ing beneath it silently costs us the TAP stream: every xt
# file ran green and emitted zero bytes, which prove6 reports as "Dubious ...
# No subtests run". Nothing is lost by skipping — test-init-nc and
# test-init-direct hand notcurses a NUL FILE* directly, so its escape
# sequences never reach stdout on Windows in the first place. Same reasoning,
# and the same conclusion, as Selkie::Test::Snapshot.
#
# INIT rather than mainline: a mainline `dup(1)` executes during
# PRECOMPILATION, in a child process, and gets baked into the precomp
# artifact — so in the process that actually runs the tests it never runs at
# all, and the redirect silently does nothing.
INIT {
	unless $*DISTRO.is-win {
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
	}
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
