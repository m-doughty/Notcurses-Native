use NativeCall;

unit module Notcurses::Native::Str;

#|( Helpers for safely transferring C-allocated char* across the
    NativeCall boundary into Raku-owned C<Str>s.

    Notcurses returns C<char*> from many calls with three distinct
    ownership semantics, and using C<--> Str> on the binding only
    works for one of them:

    =item B<malloc'd, caller frees> (e.g. C<notcurses_at_yx>,
        C<notcurses_detected_terminal>, C<nccell_strdup>) — the C
        function strdups; the caller must C<free(3)> the returned
        pointer. C<--> Str> would copy and leak the original.
        Use C<strdup-copy-and-free>.

    =item B<pointer into a caller-provided buffer> (e.g. the
        C<ncnmetric> / C<ncqprefix> family) — the returned pointer
        is inside the C<CArray[uint8] $buf> the caller passed in.
        Freeing it would corrupt the buf. Use C<borrowed-str-from-pointer>.

    =item B<pointer into library-owned memory> (e.g. C<ncplane_name>,
        C<ncselector_selected>, C<nccell_extended_gcluster>) — the
        pointer is into notcurses's internal storage; the caller MUST
        NOT free. C<--> Str> works (Raku copies and never frees the
        original), so these bindings stay unchanged. )

# libc resolver, shared with Notcurses::Native (used by both the free
# helper here and the setenv wrapper there). Resolved at BEGIN time —
# the file shipped on disk doesn't change between BEGIN and runtime, so
# this is safe to cache. Defers the actual library lookup to NativeCall.
sub libc-name(--> Str) is export {
    state $resolved = do {
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
    };
    $resolved
}

sub c-free(Pointer $p) is export
    is native(&libc-name) is symbol('free') { * }

#|( Decode a malloc'd C string into a Raku-owned C<Str> and free the
    original pointer. Returns the type object C<Str> on a null pointer.

    Use as the wrapper around any notcurses binding whose contract is
    "caller frees the returned char*". The binding should be declared
    with C<--> Pointer> instead of C<--> Str> so NativeCall doesn't
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
