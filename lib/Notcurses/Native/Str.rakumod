use NativeCall;

unit module Notcurses::Native::Str;

#|( Helpers for safely transferring C-allocated char* across the
    NativeCall boundary into Raku-owned C<Str>s.

    Notcurses returns C<char*> from many calls with three distinct
    ownership semantics, and using C«--> Str» on the binding only
    works for one of them:

    =item B<malloc'd, caller frees> (e.g. C<notcurses_at_yx>,
        C<notcurses_detected_terminal>, C<nccell_strdup>,
        C<ncplane_name>) — the C function strdups; the caller must
        C<free(3)> the returned pointer. C«--> Str» would copy and
        leak the original. Use C<strdup-copy-and-free>.

    =item B<pointer into a caller-provided buffer> (e.g. the
        C<ncnmetric> / C<ncqprefix> family) — the returned pointer
        is inside the C<CArray[uint8] $buf> the caller passed in.
        Freeing it would corrupt the buf. Use C<borrowed-str-from-pointer>.

    =item B<pointer into library-owned memory> (e.g.
        C<ncselector_selected>, C<nccell_extended_gcluster>) — the
        pointer is into notcurses's internal storage; the caller MUST
        NOT free. C«--> Str» works (Raku copies and never frees the
        original), so these bindings stay unchanged.

    Not every library-owned buffer is a NUL-terminated string.
    C<ncpile_render_to_buffer> lends out notcurses's own output
    buffer together with a byte count, and that buffer carries no
    terminator; C<borrowed-buf-from-pointer> copies exactly the
    reported bytes. (C<ncplane_name> sat in the library-owned list
    above until 0.6.7, which was wrong: notcurses hands back a fresh
    heap copy, and every call leaked it.) )

# libc resolver, shared with Notcurses::Native (used by both the free
# helper here and the setenv wrapper there). Memoised per process: the
# probes below look at files that don't change under a running program,
# so one answer serves the whole process. The actual library lookup is
# still deferred to NativeCall.
#
# The memo is lock-guarded, and it has to be. This was a plain
# `state $resolved = do { … }` until 0.6.7, and a bare `state`
# initialiser is not thread-safe: the slot is marked initialised
# independently of the value landing in it, so a thread arriving
# mid-initialisation reads `Any` — which the `--> Str` constraint then
# reports as a return type check failure, and which without that
# constraint would reach dlopen as a library name. Every string coming
# back from notcurses goes through c-free, so this resolver is on the
# path of every thread in a TUI; a burst of them touching it cold
# together is an ordinary startup, not an exotic case.
#
# Primed at the foot of this unit so the first touch happens on the
# loading thread and the race cannot arise at all. Same treatment as
# the notcurses library resolvers in Notcurses::Native.
my Lock $libc-name-lock = Lock.new;
my Str  $libc-name;
my Bool $libc-name-resolved = False;

# The probe itself, unchanged — split out of libc-name so the memo
# around it stays readable.
my sub _probe-libc-name(--> Str) {
    if $*DISTRO.is-win {
        # Windows prebuilts and source builds use the Universal CRT.
        # Heap pointers returned by notcurses must be released by the
        # same CRT family that allocated them; msvcrt.dll's free() can
        # corrupt the process heap when handed a UCRT allocation.
        'ucrtbase.dll'
    }
    elsif $*KERNEL.name.lc.contains('darwin') {
        'libc.dylib'
    }
    elsif '/lib/ld-musl-x86_64.so.1'.IO.e {
        # musl Alpine / distroless — libc is the dynamic linker
        # itself, exposed under architecture-specific filenames.
        'libc.musl-x86_64.so.1'
    }
    elsif '/lib/ld-musl-aarch64.so.1'.IO.e {
        'libc.musl-aarch64.so.1'
    }
    else {
        'libc.so.6'
    }
}

sub libc-name(--> Str) is export {
    # `//=` on the lock as well as the mainline initialiser above:
    # a unit's INIT phasers run before its mainline, so a dependent
    # unit's INIT could in principle call in before the assignment.
    ($libc-name-lock //= Lock.new).protect: {
        unless $libc-name-resolved {
            $libc-name = _probe-libc-name();
            $libc-name-resolved = True;
        }
        $libc-name
    }
}

sub c-free(Pointer $p) is export
    is native(&libc-name) is symbol('free') { * }

#|( Decode a malloc'd C string into a Raku-owned C<Str> and free the
    original pointer. Returns the type object C<Str> on a null pointer.

    Use as the wrapper around any notcurses binding whose contract is
    "caller frees the returned char*". The binding should be declared
    with C«--> Pointer» instead of C«--> Str» so NativeCall doesn't
    auto-decode-and-leak. )
sub strdup-copy-and-free(Pointer $p --> Str) is export {
    return Str unless $p.defined && +$p;
    my $s = nativecast(Str, $p);
    c-free($p);
    $s
}

#|( Decode a borrowed C-string pointer into a Raku-owned C<Str> WITHOUT
    freeing the source. Use when the pointer is into a caller-provided
    buffer or library-owned storage. Returns C<Str> (type object) on
    null. )
sub borrowed-str-from-pointer(Pointer $p --> Str) is export {
    return Str unless $p.defined && +$p;
    nativecast(Str, $p)
}

# void *memcpy(void *dest, const void *src, size_t n), bound once per
# argument shape so each copy direction gets the right marshalling.
# NativeCall hands a native function a Blob/Buf argument as a pointer
# straight at the array's storage, and the calling thread cannot reach
# a GC safepoint until the call returns, so a pre-sized buf is a valid
# memcpy destination. One bulk copy instead of a Raku loop over a
# CArray view matters here: render buffers and RGBA planes run to
# megabytes, and a per-element loop costs thousands of times more.
#
# libc-name is the resolver to use and not a bare `is native`: an empty
# library name finds memcpy through dlopen(NULL) on POSIX, but on
# Windows it resolves against the raku executable's own export table,
# which has no memcpy. libc-name answers 'ucrtbase.dll' there.
sub _memcpy-into-blob(Blob, Pointer, size_t --> Pointer)
    is native(&libc-name) is symbol('memcpy') { * }
sub _memcpy-between-pointers(Pointer, Pointer, size_t --> Pointer)
    is native(&libc-name) is symbol('memcpy') { * }
sub _memcpy-from-blob(Pointer, Blob, size_t --> Pointer)
    is native(&libc-name) is symbol('memcpy') { * }

#|( Copy the first C<$bytes> bytes of the Raku-owned C<$src> (any
    C<Blob>/C<Buf>) into native memory at C<$dest>, which the caller
    vouches holds at least C<$bytes> bytes. Dies on a negative count, on
    a count larger than C<$src>, and on a NULL destination with a
    non-zero count; a zero count touches nothing. The option structs use
    it to fill their string buffers in one call rather than a Raku loop
    over the bytes. Exported under the C<:INTERNAL> tag only. )
sub copy-blob-into-native(Pointer $dest, Blob:D $src, Int:D $bytes --> Nil)
    is export(:INTERNAL)
{
    die "copy-blob-into-native: byte count must be non-negative, got $bytes"
        if $bytes < 0;
    return if $bytes == 0;
    die "copy-blob-into-native: source holds {$src.bytes} bytes, "
      ~ "cannot supply $bytes"
        if $src.bytes < $bytes;
    die "copy-blob-into-native: NULL destination for a {$bytes}-byte copy"
        unless $dest.defined && +$dest;
    _memcpy-from-blob($dest, $src, $bytes);
    Nil
}

#|( Copy C<$bytes> bytes from native memory at C<$src> into the storage
    of the Raku-owned C<$dest> (any C<Blob>/C<Buf> type, allocated by
    the caller to at least C<$bytes> bytes). The source is only read;
    its ownership is untouched. Dies on a negative count, on a
    destination too small for the copy, and on a NULL source with a
    non-zero count. A zero count copies nothing and never touches
    either pointer. Internal plumbing for the dist's own copy-out
    wrappers, so it is exported under the C<:INTERNAL> tag only. )
sub copy-native-into-blob(Blob:D $dest, Pointer $src, Int:D $bytes --> Nil)
    is export(:INTERNAL)
{
    die "copy-native-into-blob: byte count must be non-negative, got $bytes"
        if $bytes < 0;
    return if $bytes == 0;
    die "copy-native-into-blob: destination holds {$dest.bytes} bytes, "
      ~ "cannot receive $bytes"
        if $dest.bytes < $bytes;
    die "copy-native-into-blob: NULL source for a {$bytes}-byte copy"
        unless $src.defined && +$src;
    _memcpy-into-blob($dest, $src, $bytes);
    Nil
}

#|( Copy C<$bytes> bytes between two native allocations — for example
    from a notcurses-allocated struct into the body of a Raku-created
    CStruct, reached with C<nativecast(Pointer, $struct)>. Same
    argument checks as C<copy-native-into-blob>; the caller vouches
    that both regions hold C<$bytes> bytes and do not overlap.
    Exported under the C<:INTERNAL> tag only. )
sub copy-native-between(Pointer $dest, Pointer $src, Int:D $bytes --> Nil)
    is export(:INTERNAL)
{
    die "copy-native-between: byte count must be non-negative, got $bytes"
        if $bytes < 0;
    return if $bytes == 0;
    die "copy-native-between: NULL destination for a {$bytes}-byte copy"
        unless $dest.defined && +$dest;
    die "copy-native-between: NULL source for a {$bytes}-byte copy"
        unless $src.defined && +$src;
    _memcpy-between-pointers($dest, $src, $bytes);
    Nil
}

#|( Copy exactly C<$bytes> bytes starting at the borrowed pointer C<$p>
    into a fresh, Raku-owned C<buf8>, WITHOUT freeing the source. The
    counterpart of C<borrowed-str-from-pointer> for memory that is not
    a NUL-terminated string: a length-delimited buffer the library
    lends out and keeps. C<ncpile_render_to_buffer>'s output buffer is
    the motivating case — it carries no terminator, so reading it with
    C<nativecast(Str, …)> runs past the frame into whatever an earlier,
    longer frame left behind.

    The returned buf has no tie to C<$p>; the library may reuse or
    free its buffer the moment this returns. Decode it yourself when it
    holds text (C<$buf.decode('utf8')>). See MEMORY OWNERSHIP in the
    README for worked examples.

    A zero count answers an empty C<buf8> whatever C<$p> is. Dies on a
    negative count, or on a NULL pointer paired with a non-zero count:
    both are contract violations by whatever produced the pair, and
    answering an empty buf would hide a real bug. )
sub borrowed-buf-from-pointer(Pointer $p, Int:D $bytes --> buf8) is export {
    die "borrowed-buf-from-pointer: byte count must be non-negative, got $bytes"
        if $bytes < 0;
    return buf8.new if $bytes == 0;
    die "borrowed-buf-from-pointer: NULL pointer paired with $bytes bytes"
        unless $p.defined && +$p;
    my $out = buf8.allocate($bytes);
    _memcpy-into-blob($out, $p, $bytes);
    $out
}

# One C printf conversion specification, per C99 7.19.6.1 plus the POSIX
# `n$` argument index: flags, width, precision, length modifier and the
# conversion letter. `%%` is matched as its own alternative so a literal
# percent sign is never mistaken for the start of a conversion.
my regex c-conversion {
    '%'
    [
    | $<literal>='%'
    | $<argnum>=[ \d+ '$' ]?
      $<flags>=[ <[\-+#0\x20']>* ]
      $<width>=[ \d+ | '*' [ \d+ '$' ]? ]?
      $<precision>=[ '.' [ \d+ | '*' [ \d+ '$' ]? ]? ]?
      $<length>=[ 'hh' | 'h' | 'll' | 'l' | 'j' | 'z' | 't' | 'L' | 'q' ]?
      $<conversion>=<[a..zA..Z]>
    ]
}

#|( Format C<@args> with the C printf-style C<$format> and answer the
    result, formatted by Raku's C<sprintf> rather than C's. This is what
    the C<ncplane_printf*> and C<ncdirect_printf_aligned> wrappers use in
    place of calling notcurses's variadic functions: NativeCall cannot
    call a C variadic function safely (a call with no variadic arguments
    always dies, and on Windows every integer or pointer vararg is
    passed as a 32-bit C<long>), so the text is formatted here and handed
    to a fixed-arity notcurses call.

    Formats written for C work unchanged. C length modifiers
    (C<hh h l ll j z t L q>) are accepted and dropped: Raku integers do
    not overflow, so C<%lld> formats a value beyond 2**32 correctly on
    every platform, and C<%hhd> does not truncate to a byte as C would.
    C<%n> dies, since it writes through a pointer argument, which has no
    meaning for a Raku value; so does C<%p> (format an address yourself,
    C<sprintf('0x%x', +$pointer)>), and so do the wide-character
    conversions C<%ls>, C<%lc>, C<%S> and C<%C> (pass a C<Str> to C<%s>,
    or a codepoint to C<%c>). Everything else goes to Raku's C<sprintf>
    as written, which dies on a conversion it does not know and on an
    argument count that does not match the format, where C would read
    garbage. Widths and precisions count characters (graphemes), not
    bytes: C<%5s> pads C<"é"> with four spaces where C would pad with
    three.

    C<$caller> names the function in error messages. Exported under the
    C<:INTERNAL> tag. )
sub c-sprintf(Str:D $format, @args, Str:D :$caller = 'c-sprintf' --> Str:D)
    is export(:INTERNAL)
{
    my Str $raku-format = $format.subst(&c-conversion, -> $m {
        if $m<literal> {
            '%%'
        }
        else {
            my Str $conversion = ~$m<conversion>;
            my Str $length     = ~$m<length>;
            die "$caller: '%n' is not supported in the format '$format' — "
              ~ "it writes through a pointer argument, which has no meaning "
              ~ "for a Raku value. The call answers the columns it wrote; "
              ~ "use that instead."
                if $conversion eq 'n';
            die "$caller: '%p' is not supported in the format '$format' — "
              ~ "format the address explicitly, e.g. sprintf('0x%x', +\$pointer)."
                if $conversion eq 'p';
            die "$caller: the wide-character conversion '{$m.Str}' is not "
              ~ "supported in the format '$format' — pass a Str to '%s' "
              ~ "(or a codepoint to '%c') instead."
                if $conversion eq 'S' | 'C'
                    || ($length eq 'l' && $conversion eq 's' | 'c');
            '%' ~ $m<argnum> ~ $m<flags> ~ $m<width> ~ $m<precision>
                ~ $conversion
        }
    }, :g);
    sprintf($raku-format, |@args)
}

# Prime the memo on the loading thread, so no consumer thread ever
# meets it cold. The lock makes a concurrent first touch correct;
# priming makes it not happen. Mainline rather than an INIT phaser
# deliberately: INIT runs before this unit's own mainline, which is
# where the lock above is built.
libc-name();
