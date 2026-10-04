use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native::Str;

unit module Notcurses::Native;

# === Library paths ===
# We load three notcurses libs: core (the operational API, including
# visual/blit), full (notcurses_init/ncdirect_init plus the FFmpeg
# dependency closure), and ffi (C wrappers for static-inline functions).
# NativeCall picks the library that actually exports each binding.
#
# We deliberately do NOT use %?RESOURCES for the libs themselves. zef
# stages every resource under a SHA-keyed filename, which breaks the
# inter-dylib references baked into notcurses (@loader_path/libnotcurses
# -core.3.0.17.dylib etc) — the loader can't find sibling libs by their
# real names because they've all been renamed to opaque hashes.
#
# Instead, Build.rakumod stages the libs to a stable XDG-style data
# dir at install time, under their real filenames. The dir is versioned
# by BINARY_TAG (which is small enough to survive %?RESOURCES intact)
# so a downgrade lines up with the right libs.
#
# Lookup precedence (per library):
#   1. $NOTCURSES_NATIVE_LIB_DIR env var — explicit override. Full
#      path to a directory containing all the libs. Escape hatch for
#      developers compiling notcurses themselves.
#
#      CRITICAL: the libnotcurses we ship is patched (see the fork
#      pinned by NOTCURSES_FORK for the ncvisual_blit_internal
#      begy/begx fix at 0.3.0, in src/lib/visual.c). The patch is
#      ABI-compatible at the C-symbol level — every export has the
#      same signature — but BEHAVIOURALLY divergent: a clipped
#      sprixel blit on vanilla 3.0.17 renders the top of the source
#      regardless of begy. Pointing this override at a stock
#      system-installed libnotcurses silently misrenders any chat
#      avatar / image that's clipped at a viewport edge.
#
#      If you're using the override, point it at a notcurses build
#      that includes the same patch (the fork at the URL/SHA in
#      NOTCURSES_FORK is the reference). The shim ($shim-lib) must
#      also be present in the same directory for Selkie's batched
#      copy path to engage — see src/notcurses_native_shim.c.
#   2. $NOTCURSES_NATIVE_DATA_DIR — base dir for the staged install
#      (defaults to $XDG_DATA_HOME, falling back to platform-typical).
#      Combined with BINARY_TAG to pick the version-matched libs.

constant $os is export = $*KERNEL.name.lc;
constant $ext is export = $os ~~ /darwin/ ?? 'dylib'
                       !! $*DISTRO.is-win ?? 'dll'
                       !! 'so';

# Where Build.rakumod staged the libs at install time. Must mirror
# Build.rakumod's !staged-lib-dir exactly — both compute the same path
# from the same env vars + the same BINARY_TAG (read from %?RESOURCES,
# the one resource that survives zef's hashing intact since it's a
# plain text file with no inter-file refs).
sub _staged-lib-dir(--> IO::Path) {
    my $res = %?RESOURCES<BINARY_TAG>;
    my Str $tag = ($res.defined && $res.IO.e) ?? $res.IO.slurp.trim !! '';
    my Str $base = %*ENV<NOTCURSES_NATIVE_DATA_DIR>
        // %*ENV<XDG_DATA_HOME>
        // ($*DISTRO.is-win
                ?? (%*ENV<LOCALAPPDATA>
                        // "{%*ENV<USERPROFILE> // '.'}\\AppData\\Local")
                !! "{%*ENV<HOME> // '.'}/.local/share");
    "$base/Notcurses-Native/$tag/lib".IO;
}

# Resolve a single lib by basename (without extension) within a given
# directory. Tries exact `lib.$ext` first, then versioned variants
# (libfoo.3.dylib, libfoo.so.3, libfoo-3.dll, etc) so we accept whatever
# the prebuilt archive shipped — symlinks, versioned files, both.
sub _find-in(IO::Path $dir, Str $name --> Str) {
    return Str unless $dir.d;
    my $exact = $dir.add("$name.$ext");
    return $exact.Str if $exact.e;

    for $dir.dir -> $entry {
        next unless $entry.e;  # accept symlinks + regular files
        my $bn = $entry.basename;
        return $entry.Str if $bn.starts-with("$name.") && $bn.contains(".$ext");
        return $entry.Str if $bn.starts-with("$name-") && $bn.ends-with(".$ext");
    }
    Str;
}

sub _resolve-lib(Str $name --> Str) {
    # 1. Env-override wins outright.
    if (my $override = %*ENV<NOTCURSES_NATIVE_LIB_DIR>) && $override.IO.d {
        with _find-in($override.IO, $name) { return $_ }
    }
    # 2. Staged install dir.
    with _find-in(_staged-lib-dir(), $name) { return $_ }

    # Nothing worked. Return the staged path as a hint for the
    # NativeCall error message — the user will see it in the
    # "Cannot locate native library 'X'" failure.
    "{ _staged-lib-dir() }/$name.$ext";
}

sub _absolute-io(IO() $path --> IO::Path) is export(:INTERNAL) {
    $path.IO.absolute.IO;
}

# Pick the directory whose libraries the resolver will use. This must
# stay in lockstep with _resolve-lib: the explicit override wins when it
# names a real directory, otherwise the BINARY_TAG-keyed staged dir wins.
sub _resolve-lib-dir(--> IO::Path) {
    if (my $override = %*ENV<NOTCURSES_NATIVE_LIB_DIR>) && $override.IO.d {
        return _absolute-io($override);
    }
    my $staged = _staged-lib-dir();
    return _absolute-io($staged) if $staged.d;
    IO::Path;
}

# Windows does not search the directory of a DLL loaded by absolute path
# when resolving that DLL's imports. NativeCall ultimately uses the normal
# LoadLibrary path, so loading C:\...\libnotcurses.dll can still fail with
# ERROR_MOD_NOT_FOUND even while every required FFmpeg/notcurses DLL is
# beside it.
#
# Prebuilt stages carry a closed sibling dependency set, so load them with
# LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR plus the safe default directories. Source
# builds are explicitly marked by Build.rakumod: their notcurses DLLs retain
# ordinary MSYS2 dependencies, so LOAD_WITH_ALTERED_SEARCH_PATH gives the
# target DLL's directory priority and then uses the documented ordinary search
# path, including PATH. The modes are deliberately mutually exclusive.
#
# Both paths avoid SetDllDirectoryW: Windows exposes only one such
# process-global slot, so using it here would silently evict a directory
# installed by another FFI package (or be evicted by one later).
my constant $SOURCE_BUILD_MARKER = '.notcurses-native-source-build';
my constant $LOAD_WITH_ALTERED_SEARCH_PATH = 0x00000008;
my constant $LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR = 0x00000100;
my constant $LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000;

sub _windows-load-flags(IO() $path --> uint32) is export(:INTERNAL) {
    $path.IO.parent.add($SOURCE_BUILD_MARKER).f
        ?? $LOAD_WITH_ALTERED_SEARCH_PATH
        !! $LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR
            +| $LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;
}

sub _windows-staged-load-mode(--> Str) is export(:INTERNAL) {
    _staged-lib-dir().add($SOURCE_BUILD_MARKER).f
        ?? 'source'
        !! 'prebuilt';
}

sub _LoadLibraryExW(
    Str is encoded('utf16'),
    Pointer,
    uint32
    --> Pointer
) is native('kernel32') is symbol('LoadLibraryExW') { * }

sub _GetLastError(--> uint32)
    is native('kernel32') is symbol('GetLastError') { * }

sub _prepare-windows-lib(Str $path --> Str) {
    return $path unless $*DISTRO.is-win;

    my IO::Path $absolute = _absolute-io($path);
    # Preserve _resolve-lib's actionable missing-path fallback. NativeCall
    # will report that exact path if installation/staging did not happen.
    return $path unless $absolute.e;

    my uint32 $flags = _windows-load-flags($absolute);
    my Str $load-contract = $flags == $LOAD_WITH_ALTERED_SEARCH_PATH
        ?? 'source-build directory plus ordinary PATH dependencies'
        !! 'prebuilt sibling dependency closure';

    # Resolve the GetLastError binding before the load attempt. Doing that
    # for the first time after a failure could itself touch loader state and
    # obscure the error code set by LoadLibraryExW.
    _GetLastError();
    my Pointer $handle = _LoadLibraryExW(
        $absolute.Str,
        Pointer,
        $flags,
    );
    unless $handle.defined {
        my uint32 $error = _GetLastError();
        die "Notcurses::Native: Windows could not load '{$absolute.Str}' "
          ~ "using its $load-contract (Win32 error $error).";
    }

    $absolute.Str;
}

sub _resolve-and-prepare-lib(Str $name --> Str) {
    _prepare-windows-lib(_resolve-lib($name));
}

# --- Runtime env setup ---
#
# Our bundled libncursesw was compiled against Homebrew's ncurses,
# which bakes the terminfo search path to the Homebrew cellar
# (e.g. /opt/homebrew/opt/ncurses/share/terminfo/). On a system
# without Homebrew ncurses installed, that path doesn't exist and
# ncurses can't find terminal definitions — notcurses_core_init
# fails with "No terminal available" even though the libraries
# loaded fine.
#
# macOS ships a system terminfo at /usr/share/terminfo/ with
# standard entries (xterm, screen, etc.). Set TERMINFO_DIRS so
# ncurses searches the system dir regardless of what's baked in.
# Linux has /usr/share/terminfo/ (or /lib/terminfo/ on some
# distros) and typically doesn't need the override (ncurses's
# compiled-in default already points there), but including it
# doesn't hurt. Respects a user-set TERMINFO_DIRS.
#
# Same Raku-%*ENV-doesn't-reach-C-getenv issue as Vips-Native:
# ncurses reads TERMINFO_DIRS via getenv(3), so we call setenv(3)
# directly via NativeCall. Uses the unified libc resolver in
# Notcurses::Native::Str so musl Alpine + glibc Linux + macOS all
# pick the right library without per-call redeclaration.
sub _setenv_c(Str, Str, int32 --> int32)
    is native(&libc-name) is symbol('setenv') { * }

sub _setenv-c(Str $name, Str $value) {
    %*ENV{$name} = $value;
    return if $*DISTRO.is-win;
    my $rv = _setenv_c($name, $value, 1);
    if $rv != 0 {
        # Stays in stderr — fires before notcurses_init takes the
        # terminal, so it's visible. Don't throw: missing TERMINFO_DIRS
        # is recoverable in some configurations (compiled-in default
        # path may work), and a hard die here masks the surrounding
        # ncurses error which is more useful.
        note "Notcurses::Native: setenv($name) returned $rv; "
           ~ "ncurses may not see the value via getenv(3).";
    }
}

sub _configure-runtime-env() {
    if $*DISTRO.is-win {
        # PATH is useful to child processes and to consumers that perform
        # their own ordinary DLL loads after importing this module. Raku's
        # runtime PATH mutation is not relied on for our NativeCall loads:
        # _prepare-windows-lib uses scoped LoadLibraryExW flags because the
        # Windows loader and the CRT can observe different environment state.
        my $lib-dir = _resolve-lib-dir();
        with $lib-dir {
            my Str $lib-str = .Str;
            # Windows names this variable 'Path', not 'PATH', and %*ENV is an
            # ordinary case-sensitive Hash — so reading %*ENV<PATH> answered
            # Nil and the branch below replaced the entire process PATH with
            # this single directory instead of prepending to it. Environment
            # names ARE case-insensitive to the OS, so the freshly created
            # 'PATH' key won and every other DLL search path vanished: any
            # library loaded after notcurses stopped resolving its own
            # dependencies (SQLCipher failing to find libcrypto was how this
            # surfaced). Update whichever spelling the host actually uses.
            my Str $key = %*ENV.keys.first({ .lc eq 'path' }) // 'PATH';
            my Str $current = %*ENV{$key} // '';
            unless $current eq $lib-str
                || $current.starts-with("$lib-str;") {
                %*ENV{$key} = $current.chars
                    ?? "$lib-str;$current"
                    !! $lib-str;
            }
        }
    }

    # A custom build owns its terminfo configuration, but its Windows DLL
    # dependency closure still needs the loader setup above.
    return if %*ENV<NOTCURSES_NATIVE_LIB_DIR>;

    unless %*ENV<TERMINFO_DIRS> {
        # Colon-separated list. Include both common system paths so
        # ncurses finds entries regardless of distro layout. Empty
        # trailing component means "the compiled-in default" — if
        # Homebrew IS installed, ncurses still searches its own
        # cellar path too.
        my $system-dirs = '/usr/share/terminfo:/usr/lib/terminfo:/lib/terminfo:';
        _setenv-c('TERMINFO_DIRS', $system-dirs);
    }
}
_configure-runtime-env();

# Library-path resolvers. Memoised subs rather than `constant`
# bindings because `constant X = _resolve-lib(...)` evaluates at
# compile time and bakes the resolved path into the precompiled
# bytecode — and Rakudo doesn't track `resources/BINARY_TAG` as a
# precomp dependency. Bumping BINARY_TAG (which moves the staged
# libs to a new versioned directory and may garbage-collect the
# previous one) doesn't invalidate the precomp, so a freshly
# installed package can still try to load libs from the *old* path.
# Doing the lookup inside the sub defers it to first call in each
# process — fresh every time, but still O(1) after the first
# invocation. Pair each binding with the resolver for the library
# that exports it (for example, `is native(&core-lib)`) so
# NativeCall invokes the resolver lazily.
#
# The memo is lock-guarded, and it has to be. These were bare
# `state $r = _resolve-and-prepare-lib(...)` one-liners until 0.6.7,
# and a `state` initialiser gives no atomicity: the slot is marked
# initialised independently of the value landing in it, so a thread
# arriving mid-initialisation reads `Any`. The initialiser is a
# directory walk (and, on Windows, a LoadLibraryExW), so the window
# is milliseconds wide on a cold page cache — and a TUI's startup is
# precisely a burst of threads binding native subs for the first
# time. Measured on an unfixed tree: 64 threads released together
# saw ~180 of 448 resolver calls answer `Any`, on 25 of 25 launches.
# What a consumer sees is a `Str` type object reaching dlopen as a
# library name, i.e. a binding that fails for no reason on some runs
# and not others.
#
# So: resolve under $lib-resolve-lock, and prime every resolver from
# the unit mainline (see _prime-lib-resolvers below) so the first
# touch happens on the loading thread. After priming the lock is
# uncontended.
#
# The lock is built here in the mainline AND defensively `//=`'d at
# the use site: a unit's INIT phasers run before its own mainline, so
# a dependent unit's INIT could in principle call a resolver before
# the assignment below has happened.
#
# The `--> Str` on each is load-bearing rather than decorative: it is
# the tripwire that turns a future memo regression into a loud type
# check failure instead of a silent dlopen of a type object.
my Lock $lib-resolve-lock = Lock.new;
my %lib-memo;

#| Run C<&compute> at most once per C<$key> per process and hand back
#| the memoised result, thread-safely. Keyed on C<:exists> so a
#| legitimately undefined answer is still only computed once.
my sub _memoise(Str:D $key, &compute) {
    ($lib-resolve-lock //= Lock.new).protect: {
        %lib-memo{$key} = compute() unless %lib-memo{$key}:exists;
        %lib-memo{$key};
    }
}

sub nc-lib(--> Str) is export {
    _memoise 'libnotcurses', { _resolve-and-prepare-lib('libnotcurses') }
}
sub ffi-lib(--> Str) is export {
    _memoise 'libnotcurses-ffi',
             { _resolve-and-prepare-lib('libnotcurses-ffi') }
}
sub core-lib(--> Str) is export {
    _memoise 'libnotcurses-core',
             { _resolve-and-prepare-lib('libnotcurses-core') }
}

#|( Resolved path to the perf shim that lives alongside the staged
    libnotcurses libs (see src/notcurses_native_shim.c +
    Build.rakumod's !try-compile-shim). Holds the primitives that
    cannot live in Raku: C<notcurses_native_copy_cells>, a hot loop
    unaffordable to express call-per-cell over NativeCall and used by
    Selkie::Widget::ViewportedCardList, plus
    C<notcurses_native_arm_terminal_guard> /
    C<notcurses_native_disarm_terminal_guard>, an C<atexit(3)>-based
    terminal restore that still fires when the VM exits without
    running any Raku (a MoarVM panic, for one), and the ABI table
    (C<notcurses_native_abi_count>, C<_key>, C<_value>): the struct
    layouts and constant values the bindings mirror, as the compiler
    sees them in the notcurses headers, which the test suite holds the
    bindings to.

    May resolve to a non-existent path if the shim wasn't compiled
    (no toolchain at install time AND prebuilt didn't include it);
    NativeCall will surface the missing-library error at first
    invocation. Every binding above is written to be tolerated when
    absent — the copy falls back to the per-cell Raku loop, and the
    guard simply isn't armed.

    Memoised sub (not a `constant`) for the same precomp-staleness
    reason as nc-lib / ffi-lib / core-lib, and lock-guarded for the
    same thread-safety reason — see those for the full rationale. )
sub shim-lib(--> Str) is export {
    _memoise 'libnotcurses_native_shim',
             { _resolve-and-prepare-lib('libnotcurses_native_shim') }
}

#|( Make the shim loadable, and answer whether it now is. Call this
    before the first C<is native(&shim-lib)> sub in a process, and
    handle a C<False> by not calling that sub at all.

    Why a shim binding can need this: on macOS the shim is built with
    C<-undefined dynamic_lookup>, so its notcurses references are
    left to the flat namespace and dyld resolves them when the shim
    is loaded — eagerly, since lazy binding was retired in dyld4. A
    process that has not yet loaded libnotcurses therefore fails the
    C<dlopen> of the shim outright, with "symbol not found in flat
    namespace". NativeCall binds one sub at a time on first call, so
    "has not yet loaded libnotcurses" is the ordinary state of a
    young process: a consumer whose first shim call comes before its
    first notcurses call (arming the terminal guard before
    C<notcurses_init>, say) hits it every time. Touching any
    core-lib sub first puts libnotcurses in the process and the shim
    loads. The Linux and Windows builds link the core library
    properly and never needed this; calling it there costs one
    version read.

    Memoised, thread-safe and non-throwing, like the resolvers above.
    C<False> means libnotcurses itself would not load, in which case
    nothing else in this module works either. )
sub ensure-shim-loadable(--> Bool) is export {
    _memoise 'shim-prerequisites', {
        # notcurses_version reads a static string out of the library:
        # the cheapest call in the ABI that proves it is mapped.
        ((try { notcurses_version(); True }) // False);
    }
}

#| Resolve all four library paths once, here, on whichever thread is
#| loading this unit — so no consumer thread ever meets a cold memo.
#|
#| Deliberately a mainline call rather than an INIT phaser. A unit's
#| INIT phasers run *before* that same unit's mainline, and this
#| unit's mainline includes C<_configure-runtime-env()>, which on
#| Windows puts the staged library directory on PATH — which is
#| exactly what a source build's DLLs need in order to resolve their
#| own dependencies when C<_prepare-windows-lib> loads them with
#| LOAD_WITH_ALTERED_SEARCH_PATH. Priming from INIT would invert that
#| order and break the Windows source-build lane. The mainline tail
#| gives the same "before any consumer, on one thread" guarantee with
#| the ordering intact.
#|
#| Each resolver is primed inside its own C<try> so priming can never
#| turn a lazy failure into a load-time one: on Windows resolution
#| also performs the LoadLibraryExW, which C<_prepare-windows-lib>
#| turns into a die when the DLL is present but unloadable. A failed
#| prime simply leaves that memo unset, and the same die resurfaces
#| at the first real use, exactly as before — which is what lets a
#| consumer keep tolerating an unloadable optional shim.
sub _prime-lib-resolvers() {
    try nc-lib();
    try ffi-lib();
    try core-lib();
    try shim-lib();
}
_prime-lib-resolvers();

# === Version ===

#| OWNED-BY-LIBRARY: static version string baked into libnotcurses;
#| caller MUST NOT free.
sub notcurses_version(--> Str)
	is native(&core-lib) is export { * }

sub notcurses_version_components(int32 $major is rw, int32 $minor is rw, int32 $patch is rw, int32 $tweak is rw)
	is native(&core-lib) is export { * }

# === Context init/stop (from libnotcurses-core, re-exported by libnotcurses) ===

sub notcurses_core_init(NotcursesOptions $opts, Pointer $fp --> NotcursesHandle)
	is native(&core-lib) is export { * }

sub notcurses_init(NotcursesOptions $opts, Pointer $fp --> NotcursesHandle)
	is native(&nc-lib) is export { * }

sub notcurses_stop(NotcursesHandle $nc --> int32)
	is native(&core-lib) is export { * }

# === Standard plane ===

sub notcurses_stdplane(NotcursesHandle $nc --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub notcurses_stdplane_const(NotcursesHandle $nc --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub notcurses_stddim_yx(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw --> NcplaneHandle)
	is native(&ffi-lib) is export { * }

# === Rendering ===

sub notcurses_render(NotcursesHandle $nc --> int32)
	is native(&ffi-lib) is export { * }

sub notcurses_refresh(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw --> int32)
	is native(&core-lib) is export { * }

# === Terminal dimensions ===

sub notcurses_term_dim_yx(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw)
	is native(&ffi-lib) is export { * }

# === Capabilities ===

sub notcurses_cantruecolor(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canfade(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canchangecolor(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canopen_images(NotcursesHandle $nc --> bool)
	is native(&core-lib) is export { * }

sub notcurses_canopen_videos(NotcursesHandle $nc --> bool)
	is native(&core-lib) is export { * }

sub notcurses_canbraille(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_cansextant(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canpixel(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canutf8(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canhalfblock(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canquadrant(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

# === Alternate screen ===

sub notcurses_enter_alternate_screen(NotcursesHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub notcurses_leave_alternate_screen(NotcursesHandle $nc --> int32)
	is native(&core-lib) is export { * }

# === Cursor ===

sub notcurses_cursor_enable(NotcursesHandle $nc, int32 $y, int32 $x --> int32)
	is native(&core-lib) is export { * }

sub notcurses_cursor_disable(NotcursesHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub notcurses_cursor_yx(NotcursesHandle $nc, int32 $y is rw, int32 $x is rw --> int32)
	is native(&core-lib) is export { * }

# === Input ===

#| Sentinel returned by every C<notcurses_get*> on error — C's C<(uint32_t)-1>.
#| These subs are bound with a C<uint32> return type, so an error arrives as
#| 4294967295 and a Raku-side C<== -1> test silently never matches. Compare
#| against this constant instead. C<0> still means "no input available".
constant NOTCURSES-GET-ERROR is export = 0xFFFFFFFF;

sub notcurses_get(NotcursesHandle $nc, Timespec $ts, Ncinput $ni --> uint32)
	is native(&core-lib) is export { * }

sub notcurses_get_nblock(NotcursesHandle $nc, Ncinput $ni --> uint32)
	is native(&ffi-lib) is export { * }

sub notcurses_get_blocking(NotcursesHandle $nc, Ncinput $ni --> uint32)
	is native(&ffi-lib) is export { * }

# === Mouse ===

sub notcurses_mice_enable(NotcursesHandle $nc, uint32 $eventmask --> int32)
	is native(&core-lib) is export { * }

sub notcurses_mice_disable(NotcursesHandle $nc --> int32)
	is native(&ffi-lib) is export { * }

# === Plane creation/destruction ===

sub ncplane_create(NcplaneHandle $parent, NcplaneOptions $opts --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_destroy(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

# === Plane dimensions ===

sub ncplane_dim_yx(NcplaneHandle $n, uint32 $rows is rw, uint32 $cols is rw)
	is native(&core-lib) is export { * }

# FFI functions for inline plane helpers
sub ncplane_dim_y(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_dim_x(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

# === Plane output ===

sub ncplane_putchar_yx(NcplaneHandle $n, int32 $y, int32 $x, uint8 $c --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putstr_yx(NcplaneHandle $n, int32 $y, int32 $x, Str $str --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, Str $str --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putnstr_yx(NcplaneHandle $n, int32 $y, int32 $x, size_t $len, Str $str --> int32)
	is native(&ffi-lib) is export { * }

# === Plane cursor ===

sub ncplane_cursor_move_yx(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native(&core-lib) is export { * }

sub ncplane_cursor_move_rel(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native(&core-lib) is export { * }

sub ncplane_cursor_yx(NcplaneHandle $n, uint32 $y is rw, uint32 $x is rw)
	is native(&core-lib) is export { * }

sub ncplane_home(NcplaneHandle $n)
	is native(&core-lib) is export { * }

# === Plane styling ===

sub ncplane_set_styles(NcplaneHandle $n, uint32 $styles)
	is native(&core-lib) is export { * }

sub ncplane_on_styles(NcplaneHandle $n, uint32 $styles)
	is native(&core-lib) is export { * }

sub ncplane_off_styles(NcplaneHandle $n, uint32 $styles)
	is native(&core-lib) is export { * }

# === Plane colors (via FFI for inline functions) ===

sub ncplane_set_fg_rgb(NcplaneHandle $n, uint32 $channel --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_bg_rgb(NcplaneHandle $n, uint32 $channel --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_fg_rgb8(NcplaneHandle $n, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_bg_rgb8(NcplaneHandle $n, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_fg_default(NcplaneHandle $n)
	is native(&core-lib) is export { * }

sub ncplane_set_bg_default(NcplaneHandle $n)
	is native(&core-lib) is export { * }

sub ncplane_set_fg_palindex(NcplaneHandle $n, uint32 $idx --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_bg_palindex(NcplaneHandle $n, uint32 $idx --> int32)
	is native(&core-lib) is export { * }

# === Plane erase ===

sub ncplane_erase(NcplaneHandle $n)
	is native(&core-lib) is export { * }

sub ncplane_erase_region(NcplaneHandle $n, int32 $ystart, int32 $xstart, int32 $ylen, int32 $xlen --> int32)
	is native(&core-lib) is export { * }

# === Plane movement/resize ===

sub ncplane_move_yx(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native(&core-lib) is export { * }

sub ncplane_resize(NcplaneHandle $n, int32 $keepy, int32 $keepx,
	uint32 $keepleny, uint32 $keeplenx,
	int32 $yoff, int32 $xoff,
	uint32 $ylen, uint32 $xlen --> int32)
	is native(&core-lib) is export { * }

# === Plane z-order ===

sub ncplane_move_top(NcplaneHandle $n)
	is native(&ffi-lib) is export { * }

sub ncplane_move_bottom(NcplaneHandle $n)
	is native(&ffi-lib) is export { * }

sub ncplane_move_above(NcplaneHandle $n, NcplaneHandle $above --> int32)
	is native(&core-lib) is export { * }

sub ncplane_move_below(NcplaneHandle $n, NcplaneHandle $below --> int32)
	is native(&core-lib) is export { * }

# === Cell functions (FFI) ===

# === Visual (implemented and exported by libnotcurses-core) ===

sub ncvisual_from_file(Str $file --> NcvisualHandle)
	is native(&core-lib) is export { * }

sub ncvisual_from_rgba(Pointer $rgba, int32 $rows, int32 $rowstride, int32 $cols --> NcvisualHandle)
	is native(&core-lib) is export { * }

sub ncvisual_destroy(NcvisualHandle $v)
	is native(&core-lib) is export { * }

sub ncvisual_decode(NcvisualHandle $v --> int32)
	is native(&core-lib) is export { * }

sub ncvisual_resize(NcvisualHandle $v, int32 $rows, int32 $cols --> int32)
	is native(&core-lib) is export { * }
