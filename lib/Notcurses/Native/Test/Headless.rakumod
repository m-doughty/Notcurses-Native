use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;
use Notcurses::Native::Direct;
use Notcurses::Native::Str;

#|( Test-only support for the C<t/> tests that need a live notcurses
    instance: run a Raku script in a child process, start notcurses
    there with no terminal at all, and report results back to the
    parent as tagged lines. Like C<Notcurses::Native::Test::Helper>,
    this ships under the dist's C<::Test> namespace rather than
    C<t/lib> so C<zef install> precompiles it with the rest of C<lib/>
    before any test runs.

    Why a child process: the behaviours these tests pin are memory-
    safety ones, and the failure mode is the process dying (a double
    free aborts, a use-after-free segfaults). A test harness has to
    survive that to report it, so the notcurses work runs in a child
    and the parent asserts on the child's exit code, its signal, and
    what it reported.

    Why "headless": notcurses takes a non-tty output C<FILE*> as its
    cue to open C</dev/tty> and interrogate the controlling terminal,
    blocking without a timeout on the replies — a hang, or a degraded
    init, whenever the suite runs from a real terminal. The child
    therefore detaches with C<setsid(2)> on POSIX before it initialises
    notcurses, so every run takes the deterministic no-terminal path
    that CI takes. On Windows the child's standard handles are all
    pipes, which the pinned notcurses fork recognises as a redirected
    harness and initialises without console interrogation.

    Parent side: C<run-headless-script>. Child side:
    C<headless-notcurses>, C<headless-ncdirect>, C<report>,
    C<current-rss-kib>, C<native-getenv>. )
unit module Notcurses::Native::Test::Headless;

sub _setsid(--> int32)
    is native(&libc-name) is symbol('setsid') { * }

sub _fopen(Str, Str --> Pointer)
    is native(&libc-name) is symbol('fopen') { * }

# The flags every headless child uses. Signal handlers stay off so a
# crash reaches the parent as the raw signal it is; input is drained so
# notcurses never competes for the child's (piped) stdin.
my constant HEADLESS-FLAGS = NCOPTION_SUPPRESS_BANNERS
    +| NCOPTION_NO_ALTERNATE_SCREEN
    +| NCOPTION_NO_QUIT_SIGHANDLERS
    +| NCOPTION_NO_WINCH_SIGHANDLER
    +| NCOPTION_DRAIN_INPUT;

# Marker that introduces every result a child reports.
my constant RESULT-TAG = 'NOTCURSES-NATIVE-RESULT';

# Distinguishes the script files of concurrent calls within one process.
my atomicint $script-serial = 0;

# Detach from the controlling terminal (POSIX; a no-op on Windows, whose
# headless children have only pipes for standard handles). EPERM means
# this process leads its process group, which a child spawned by
# run-headless-script never does; carrying on attached would risk the
# interrogation hang described above, so refuse loudly instead.
my sub detach-from-terminal(Str:D $caller --> Nil) {
    return if $*DISTRO.is-win;
    my int32 $sid = _setsid();
    die "$caller: setsid() failed ($sid); this process leads its process "
      ~ "group and would keep its controlling terminal. Run it through "
      ~ "run-headless-script."
        if $sid < 0;
}

# fopen(3) the null device for writing, or die naming the caller.
my sub open-null-device(Str:D $caller --> Pointer) {
    my Str $null-device = $*DISTRO.is-win ?? 'NUL' !! '/dev/null';
    my Pointer $out = _fopen($null-device, 'w');
    die "$caller: could not open $null-device for writing"
        unless $out.defined && +$out;
    $out
}

#|( Child side. Detach from any controlling terminal (POSIX), open the
    null device, and start notcurses core on it with the flags above.
    Answers the handle; dies with a diagnostic when any step fails,
    because a test that cannot get a notcurses instance has nothing
    meaningful to assert. Call it once per child process — notcurses
    allows one instance per process. C<:termtype> names the terminfo
    entry notcurses should use instead of C<$TERM>'s. )
sub headless-notcurses(Str :$termtype --> NotcursesHandle) is export {
    detach-from-terminal('headless-notcurses');
    my Pointer $out = open-null-device('headless-notcurses');
    my $opts = NotcursesOptions.new(
        :loglevel(NCLOGLEVEL_SILENT),
        :flags(HEADLESS-FLAGS),
        :$termtype,
    );
    my $nc = notcurses_core_init($opts, $out);
    die "headless-notcurses: notcurses_core_init failed with no terminal "
      ~ "(TERM={%*ENV<TERM> // '(unset)'}). run-headless-script sets "
      ~ "TERM when the environment lacks one; a failure here means "
      ~ "notcurses found no usable terminfo entry for it."
        unless $nc.defined;
    $nc
}

#|( Child side. The direct-mode counterpart of C<headless-notcurses>:
    detach from any controlling terminal (POSIX) and start an ncdirect
    instance with no terminal, its quit signal handlers off and input
    drained, for the same reasons. Answers the handle; dies with a
    diagnostic when any step fails. Call it at most once per child, and
    not in a child that also calls C<headless-notcurses>.

    By default the ncdirect writes to the null device. Pass C<:on-stdout>
    to have it write to the child's standard output instead — the stream
    C<ncdirect_printf_aligned> writes its text to in any case — so the
    parent can inspect its escape sequences in C<run-headless-script>'s
    C<out>. The C runtime buffers that stream, so call C<ncdirect_flush>
    before C<report>ing anything that should follow the output. )
sub headless-ncdirect(Bool :$on-stdout = False --> NcdirectHandle) is export {
    detach-from-terminal('headless-ncdirect');
    my constant FLAGS = NCDIRECT_OPTION_NO_QUIT_SIGHANDLERS
        +| NCDIRECT_OPTION_DRAIN_INPUT;
    my $d = $on-stdout
        ?? ncdirect_core_init(Str, Pointer, FLAGS)
        !! ncdirect_core_init(Str, open-null-device('headless-ncdirect'), FLAGS);
    die "headless-ncdirect: ncdirect_core_init failed with no terminal "
      ~ "(TERM={%*ENV<TERM> // '(unset)'})."
        unless $d.defined;
    $d
}

#|( Child side. Report one result to the parent as a single tagged line
    on standard output. Keys are identifiers; values must not contain a
    tab or a line break (encode binary data first, for example as hex).
    Anything else the child prints is ignored by the parent's parser. )
sub report(Str:D $key, Str() $value --> Nil) is export {
    die "report: key '$key' must be a plain identifier"
        unless $key ~~ /^ <[\w-]>+ $/;
    die "report: value for '$key' contains a tab or line break"
        if $value.contains("\t") || $value.contains("\n")
            || $value.contains("\r");
    $*OUT.put: RESULT-TAG ~ "\t$key\t$value";
    $*OUT.flush;
    Nil
}

sub _getenv(Str --> Pointer)
    is native(&libc-name) is symbol('getenv') { * }
sub _GetEnvironmentVariableA(Str, CArray[uint8], uint32 --> uint32)
    is native('kernel32') is symbol('GetEnvironmentVariableA') { * }

# The largest environment value Windows allows, terminator included.
my constant WIN-ENV-MAX = 32767;

#|( Child side. Environment variable C<$name> as native code sees it
    now: the C runtime's C<getenv(3)> on POSIX, the process environment
    block (C<GetEnvironmentVariableA>) on Windows. Unlike C<%*ENV>, which
    Raku snapshots at startup, this sees what C code has exported since —
    notcurses exports a C<termtype> option as C<TERM>, for one. Answers
    C<Str> when the variable is unset. )
sub native-getenv(Str:D $name --> Str) is export {
    if $*DISTRO.is-win {
        my $buffer = CArray[uint8].allocate(WIN-ENV-MAX + 1);
        my Int $length = _GetEnvironmentVariableA($name, $buffer, WIN-ENV-MAX + 1);
        return Str if $length == 0;
        die "native-getenv: $name is longer than Windows allows ($length)"
            if $length > WIN-ENV-MAX;
        return Blob.new((^$length).map({ $buffer[$_] })).decode('utf8-c8');
    }
    my Pointer $value = _getenv($name);
    ($value.defined && +$value) ?? nativecast(Str, $value) !! Str
}

# kernel32's K32GetProcessMemoryInfo (Windows 7 on) fills a
# PROCESS_MEMORY_COUNTERS: DWORD cb, DWORD PageFaultCount, then eight
# SIZE_Ts — 72 bytes on x64, WorkingSetSize at byte 16. Modelled as nine
# uint64 slots, so cb/PageFaultCount share slot 0 (cb in its low half on
# a little-endian machine) and WorkingSetSize is slot 2. Asked of the
# kernel directly rather than through PowerShell, whose directory is
# not on an MSYS2 shell's minimal PATH.
sub _GetCurrentProcess(--> Pointer)
    is native('kernel32') is symbol('GetCurrentProcess') { * }
sub _K32GetProcessMemoryInfo(Pointer, CArray[uint64], uint32 --> int32)
    is native('kernel32') is symbol('K32GetProcessMemoryInfo') { * }

my constant PMC-BYTES          = 72;
my constant PMC-WORKING-SET-AT = 2;

#|( Child side. The process's current resident set size in KiB, for
    coarse leak checks: C</proc/self/status> on Linux, C<ps(1)> on
    macOS and the BSDs, and the working set from
    C<K32GetProcessMemoryInfo> on Windows. Dies when the measurement
    cannot be taken — a leak check that silently read zero would pass
    forever. )
sub current-rss-kib(--> Int) is export {
    my IO::Path $status = '/proc/self/status'.IO;
    if $status.e {
        for $status.slurp.lines -> Str $line {
            with $line ~~ /^ 'VmRSS:' \s* (\d+) \s* 'kB' / {
                return +$0;
            }
        }
        die "current-rss-kib: no VmRSS line in /proc/self/status";
    }
    if $*DISTRO.is-win {
        my $counters = CArray[uint64].new(PMC-BYTES, |(0 xx 8));
        die "current-rss-kib: K32GetProcessMemoryInfo failed"
            unless _K32GetProcessMemoryInfo(_GetCurrentProcess(),
                $counters, PMC-BYTES);
        my Int $working-set = $counters[PMC-WORKING-SET-AT];
        die "current-rss-kib: K32GetProcessMemoryInfo reported no working set"
            unless $working-set > 0;
        return $working-set div 1024;
    }
    my $proc = run 'ps', '-o', 'rss=', '-p', ~$*PID, :out, :err;
    my Str $out = $proc.out.slurp(:close).trim;
    my Str $err = $proc.err.slurp(:close).trim;
    die "current-rss-kib: ps -o rss= failed (exit {$proc.exitcode}): $err"
        unless $proc.exitcode == 0 && $out ~~ /^ \d+ $/;
    $out.Int
}

#|( Parent side. Run C<$script> (Raku source) in a fresh C<raku> child
    with C<-I $lib>, collect everything it prints, and answer a Map:

    C<exitcode> and C<signal> (a signal-killed child reports exit code
    0, so a caller must check both), C<timed-out> (the child was killed
    after C<$timeout> seconds), C<out> and C<err> (the raw streams), and
    C<results> — a Hash of every C<report>ed key to its value.

    C<$lib> defaults to the C<lib/> directory beside the running test's
    parent directory, which is right for anything under C<t/>. C<%env>
    entries are added to (or override) the inherited environment. Two
    adjustments make the child independent of the shell the suite was
    started from: on POSIX, C<TERM> is filled in with C<xterm> when
    unset, since notcurses needs some terminfo entry even without a
    terminal; and a C<LANG> of exactly C<C> or C<POSIX> is dropped,
    because notcurses reads that as an instruction never to switch to a
    UTF-8 locale, and several tests write multi-byte clusters. The
    child's standard input is a pipe that is closed immediately. C<$cwd>,
    when given, is the child's working directory — its real one, which
    C code sees, unlike a C<chdir> inside the script, which only moves
    Raku's C<$*CWD>. )
sub run-headless-script(
    Str:D $script,
    IO() :$lib = $*PROGRAM.parent.parent.add('lib'),
    :%env,
    Real :$timeout = 300,
    IO() :$cwd,
    --> Map
) is export {
    my IO::Path $file = $*TMPDIR.add(
        "notcurses-native-headless-{$*PID}-{(^2**31).pick}-"
          ~ "{$script-serial⚛++}.raku");
    $file.spurt($script);
    LEAVE { try $file.unlink }

    my %child-env = %*ENV;
    unless $*DISTRO.is-win {
        %child-env<TERM> //= 'xterm';
    }
    %child-env<LANG>:delete
        if (%child-env<LANG> // '') eq 'C' | 'POSIX';
    %child-env{.key} = .value for %env;

    my $proc = Proc::Async.new(:w, $*EXECUTABLE.absolute,
        '-I', $lib.absolute, $file.absolute);
    my Str $out = '';
    my Str $err = '';
    my $lock = Lock.new;
    $proc.stdout.tap: -> $chunk { $lock.protect: { $out ~= $chunk } },
        quit => -> $ { };
    $proc.stderr.tap: -> $chunk { $lock.protect: { $err ~= $chunk } },
        quit => -> $ { };

    my Promise $done = $cwd.defined
        ?? $proc.start(:ENV(%child-env), :cwd($cwd.absolute))
        !! $proc.start(:ENV(%child-env));
    # Close stdin once the child is running, so notcurses (and anything
    # else) sees end-of-file rather than the parent's terminal.
    await $proc.ready;
    $proc.close-stdin;

    my Bool $timed-out = False;
    await Promise.anyof($done, Promise.in($timeout));
    unless $done {
        $timed-out = True;
        $proc.kill(SIGKILL);
    }
    my $result = try await $done;

    my %results;
    # The tag is searched for rather than anchored: anything else that
    # reaches the child's stdout without a newline (a library writing to
    # the standard handle, say) must not swallow the report behind it.
    for $lock.protect({ $out }).lines -> Str $line {
        my Int $at = $line.rindex(RESULT-TAG ~ "\t") // next;
        my @field = $line.substr($at).split("\t", 3);
        next unless @field == 3;
        %results{@field[1]} = @field[2];
    }

    # Test definedness, never truth: a Proc is falsy for any non-zero
    # exit, which is exactly the case that has to be reported.
    Map.new(
        'exitcode'  => ($result.defined ?? $result.exitcode !! -1),
        'signal'    => ($result.defined ?? $result.signal !! -1),
        'timed-out' => $timed-out,
        'out'       => $lock.protect({ $out }),
        'err'       => $lock.protect({ $err }),
        'results'   => %results,
    )
}

#|( Parent side. A one-line description of how a child ended, for test
    descriptions and diagnostics: "exit 0", "exit 3", "killed by signal
    11", or "timed out". )
sub describe-exit(Map:D $run --> Str) is export {
    return 'timed out' if $run<timed-out>;
    return "killed by signal {$run<signal>}" if $run<signal>;
    "exit {$run<exitcode>}"
}
