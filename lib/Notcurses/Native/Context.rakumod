use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;
use Notcurses::Native::Str :DEFAULT, :INTERNAL;

unit module Notcurses::Native::Context;

# Owner/render thread only. No repaint and no wait for terminal replies.
# Returns 0 with latest known geometry, -1 with outputs unchanged on failure.
# Requires the fork's runtime geometry API; missing symbols are not suppressed.
sub notcurses_poll_geometry(NotcursesHandle $nc, uint32 $rows is rw,
    uint32 $cols is rw, uint32 $cell-y is rw, uint32 $cell-x is rw --> int32)
    is native(&core-lib) is export { * }

# Context, pile, palette, capabilities, stats, fade, metric, utility bindings

# === String/Unicode utilities ===

sub ncstrwidth(Str $egcs, int32 $validbytes is rw, int32 $validwidth is rw --> int32)
	is native(&core-lib) is export { * }

sub notcurses_ucs32_to_utf8(CArray[uint32] $ucs32, uint32 $ucs32count, CArray[uint8] $resultbuf, size_t $buflen --> int32)
	is native(&core-lib) is export { * }

# ncwcsrtombs returns a malloc'd buffer the caller must free. Binding as
# `--> Str` would let NativeCall decode-and-leak the original pointer.
sub _ncwcsrtombs_raw(CArray[int32] $src --> Pointer)
	is native(&ffi-lib) is symbol('ncwcsrtombs') { * }

sub ncwcsrtombs(CArray[int32] $src --> Str) is export {
	strdup-copy-and-free(_ncwcsrtombs_raw($src))
}

# === Lex/string conversions for enums ===

sub notcurses_lex_margins(Str $op, NotcursesOptions $opts --> int32)
	is native(&core-lib) is export { * }

sub notcurses_lex_blitter(Str $op, int32 $blitter is rw --> int32)
	is native(&core-lib) is export { * }

#| OWNED-BY-LIBRARY: returns a pointer to a static string literal inside
#| libnotcurses; caller MUST NOT free. `--> Str` is safe — Raku copies.
sub notcurses_str_blitter(int32 $blitter --> Str)
	is native(&core-lib) is export { * }

sub notcurses_lex_scalemode(Str $op, int32 $scalemode is rw --> int32)
	is native(&core-lib) is export { * }

#| OWNED-BY-LIBRARY: static string literal; caller MUST NOT free.
sub notcurses_str_scalemode(int32 $scalemode --> Str)
	is native(&core-lib) is export { * }

# === Pile operations ===

sub ncpile_top(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncpile_bottom(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub notcurses_top(NotcursesHandle $n --> NcplaneHandle)
	is native(&ffi-lib) is export { * }

sub notcurses_bottom(NotcursesHandle $n --> NcplaneHandle)
	is native(&ffi-lib) is export { * }

sub ncpile_render(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncpile_rasterize(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

#|( Raw binding. Renders and rasterizes the pile containing C<$p> into
    memory instead of the terminal, then writes a pointer to the frame
    into C<$buf[0]> and its length in bytes into C<$buflen[0]>. Returns
    0 on success, -1 on failure.

    BORROWED — the caller MUST NOT free C<$buf[0]>. notcurses.h says
    "the returned buffer must be freed by the caller", but the
    implementation lends out its own output buffer (C<nc-E<gt>rstate.f>),
    keeps writing into it on later frames and frees it itself in
    C<notcurses_stop>; on Linux it is not even a C<malloc> allocation
    but an C<mmap>. Freeing it is a use-after-free on the next frame and
    a double free at stop. The pointer and bytes are valid only until
    the next C<notcurses_render>, C<ncpile_render_to_buffer>,
    C<ncpile_rasterize>, C<notcurses_refresh> or C<notcurses_stop> on
    the same notcurses instance.

    The frame is exactly C<$buflen[0]> bytes and is NOT NUL-terminated,
    so C<nativecast(Str, $buf[0])> reads past it into whatever an
    earlier, longer frame left in the buffer. Copy exactly C<$buflen[0]>
    bytes (C<borrowed-buf-from-pointer>), or use
    C<ncpile-render-to-blob> / C<ncpile-render-to-string>, which do. )
sub ncpile_render_to_buffer(NcplaneHandle $p, CArray[Pointer] $buf, CArray[size_t] $buflen --> int32)
	is native(&core-lib) is export { * }

#|( Render the pile containing C<$p> into memory and answer the frame as
    a Raku-owned C<buf8> holding exactly the bytes notcurses produced —
    the escape sequences and glyphs it would have written to the
    terminal. Answers the type object C<buf8> when rendering fails.

    The copy is taken before this returns, so the C<buf8> stays valid
    across later frames and after C<notcurses_stop>; nothing is freed
    here, because the buffer belongs to notcurses (see
    C<ncpile_render_to_buffer>). A frame with nothing to draw is an
    empty C<buf8>, not a failure.

    Prefer this over C<ncpile-render-to-string> when the bytes matter
    as bytes: diffing frames, hashing them, or replaying them to a
    terminal. Decoding into a C<Str> normalises text (NFC, and C<\r\n>
    becomes one grapheme), so C<.encode> of the string is not
    guaranteed to reproduce the frame byte for byte. See MEMORY
    OWNERSHIP in the README for a worked example. )
sub ncpile-render-to-blob(NcplaneHandle $p --> buf8) is export {
	my $buf-out = CArray[Pointer].new(Pointer);
	my $len-out = CArray[size_t].new(0);
	return buf8 if ncpile_render_to_buffer($p, $buf-out, $len-out) < 0;
	# Copy exactly the reported length out of notcurses's own buffer.
	# Never free it: notcurses reuses it for the next frame and frees it
	# in notcurses_stop.
	borrowed-buf-from-pointer($buf-out[0], $len-out[0])
}

#|( Render the pile containing C<$p> into memory and answer the frame
    decoded as UTF-8: the escape sequences and glyphs notcurses would
    have written to the terminal. Answers the type object C<Str> when
    rendering fails, and C<''> for a frame with nothing to draw.

    The result is a Raku-owned copy and the caller has nothing to free.
    Earlier versions freed notcurses's output buffer here — a
    use-after-free on the next frame and a double free at
    C<notcurses_stop>, because the buffer belongs to the library — and
    read it as a NUL-terminated string although it carries no
    terminator, so a short frame came back with the tail of an earlier,
    longer one attached. Both are fixed: the frame is exactly the bytes
    notcurses reported.

    Decoding is strict: a frame that is not valid UTF-8 dies rather than
    being repaired. Use C<ncpile-render-to-blob> for byte-exact output. )
sub ncpile-render-to-string(NcplaneHandle $p --> Str) is export {
	my buf8 $frame = ncpile-render-to-blob($p);
	return Str without $frame;
	$frame.decode('utf8')
}

# fp is FILE*
sub ncpile_render_to_file(NcplaneHandle $p, Pointer $fp --> int32)
	is native(&core-lib) is export { * }

sub ncpile_create(NotcursesHandle $nc, NcplaneOptions $nopts --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub notcurses_drop_planes(NotcursesHandle $nc)
	is native(&core-lib) is export { * }

# === Input ===

sub notcurses_getvec(NotcursesHandle $n, Timespec $ts, Ncinput $ni, int32 $vcount --> int32)
	is native(&core-lib) is export { * }

sub notcurses_inputready_fd(NotcursesHandle $n --> int32)
	is native(&core-lib) is export { * }

sub notcurses_linesigs_disable(NotcursesHandle $n --> int32)
	is native(&core-lib) is export { * }

sub notcurses_linesigs_enable(NotcursesHandle $n --> int32)
	is native(&core-lib) is export { * }

# === Standard plane (const variant) ===

sub notcurses_stddim_yx_const(NotcursesHandle $nc, uint32 $y is rw, uint32 $x is rw --> NcplaneHandle)
	is native(&ffi-lib) is export { * }

# Returns a heap-allocated EGC string that the caller must free.
sub _notcurses_at_yx_raw(NotcursesHandle $nc, uint32 $yoff, uint32 $xoff, uint16 $stylemask is rw, uint64 $channels is rw --> Pointer)
	is native(&core-lib) is symbol('notcurses_at_yx') { * }

sub notcurses_at_yx(NotcursesHandle $nc, uint32 $yoff, uint32 $xoff, uint16 $stylemask is rw, uint64 $channels is rw --> Str) is export {
	strdup-copy-and-free(_notcurses_at_yx_raw($nc, $yoff, $xoff, $stylemask, $channels))
}

# === Palette ===

sub ncpalette_new(NotcursesHandle $nc --> NcpaletteHandle)
	is native(&core-lib) is export { * }

sub ncpalette_use(NotcursesHandle $nc, NcpaletteHandle $p --> int32)
	is native(&core-lib) is export { * }

sub ncpalette_set_rgb8(NcpaletteHandle $p, int32 $idx, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native(&ffi-lib) is export { * }

sub ncpalette_set(NcpaletteHandle $p, int32 $idx, uint32 $rgb --> int32)
	is native(&ffi-lib) is export { * }

sub ncpalette_get(NcpaletteHandle $p, int32 $idx, uint32 $palent is rw --> int32)
	is native(&ffi-lib) is export { * }

sub ncpalette_get_rgb8(NcpaletteHandle $p, int32 $idx, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> int32)
	is native(&ffi-lib) is export { * }

sub ncpalette_free(NcpaletteHandle $p)
	is native(&core-lib) is export { * }

# === Capabilities & terminal info ===

sub notcurses_supported_styles(NotcursesHandle $nc --> uint16)
	is native(&core-lib) is export { * }

sub notcurses_palette_size(NotcursesHandle $nc --> uint32)
	is native(&core-lib) is export { * }

# Returns a heap-allocated terminal name that the caller must free.
sub _notcurses_detected_terminal_raw(NotcursesHandle $nc --> Pointer)
	is native(&core-lib) is symbol('notcurses_detected_terminal') { * }

sub notcurses_detected_terminal(NotcursesHandle $nc --> Str) is export {
	strdup-copy-and-free(_notcurses_detected_terminal_raw($nc))
}

sub notcurses_capabilities(NotcursesHandle $n --> Nccapabilities)
	is native(&core-lib) is export { * }

# Returns ncpixelimpl_e (enum as int32)
sub notcurses_check_pixel_support(NotcursesHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub nccapability_canchangecolor(Nccapabilities $caps --> bool)
	is native(&ffi-lib) is export { * }

sub notcurses_canoctant(NotcursesHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

# === Statistics ===

#|( Raw binding. Allocates an uninitialised C<ncstats> with C<malloc(3)>
    — notcurses wants callers to use this rather than sizing the struct
    themselves, because later versions may enlarge it. CALLER FREES: the
    returned C<Ncstats> wraps C memory that nothing on the Raku side
    will ever release, so pair every call with C<notcurses-stats-free>.
    The contents are garbage until C<notcurses_stats> fills them. Most
    callers want C<notcurses-stats-snapshot> instead, which does the
    whole allocate/fill/copy/free dance and returns a Raku-owned
    struct. Answers the C<Ncstats> type object if the allocation fails. )
sub notcurses_stats_alloc(NotcursesHandle $nc --> Ncstats)
	is native(&core-lib) is export { * }

#|( Release an C<Ncstats> obtained from C<notcurses_stats_alloc>. Only
    ever pass structs that came from C<notcurses_stats_alloc>: one made
    with C<Ncstats.new> belongs to the VM, and handing it to C<free(3)>
    corrupts the process heap. Using the struct after this call is a
    use-after-free. A type object (the failed-allocation result) is
    accepted and ignored, so the call can sit unconditionally in a
    C<LEAVE>. )
sub notcurses-stats-free(Ncstats $stats --> Nil) is export {
	return without $stats;
	c-free(nativecast(Pointer, $stats));
	Nil
}

#|( Answer the notcurses instance's current statistics as a Raku-owned
    C<Ncstats>, with nothing left for the caller to free.

    It allocates through C<notcurses_stats_alloc> (so notcurses sizes the
    struct, even if a future version enlarges it), fills it with
    C<notcurses_stats>, copies the fields this binding knows into the
    result, and frees the C allocation before returning.

    Pass C<:into> to reuse one C<Ncstats> across calls — worth doing on a
    per-frame path, because MoarVM never releases the C body behind an
    C<Ncstats.new>, so each fresh struct costs its size for the life of
    the process. Without C<:into> a new struct is created per call.
    Dies if notcurses cannot allocate the temporary struct. )
sub notcurses-stats-snapshot(NotcursesHandle $nc, Ncstats :$into --> Ncstats) is export {
	my Ncstats $target = $into // Ncstats.new;
	my Ncstats $scratch = notcurses_stats_alloc($nc);
	die 'notcurses-stats-snapshot: notcurses_stats_alloc could not '
	  ~ 'allocate a stats struct'
		without $scratch;
	LEAVE notcurses-stats-free($scratch);
	notcurses_stats($nc, $scratch);
	copy-native-between(nativecast(Pointer, $target),
		nativecast(Pointer, $scratch), nativesizeof(Ncstats));
	$target
}

sub notcurses_stats(NotcursesHandle $nc, Ncstats $stats)
	is native(&core-lib) is export { * }

sub notcurses_stats_reset(NotcursesHandle $nc, Ncstats $stats)
	is native(&core-lib) is export { * }

# === Alignment ===

sub notcurses_align(int32 $availu, int32 $align, int32 $u --> int32)
	is native(&ffi-lib) is export { * }

# === Fade context ===

sub ncfadectx_setup(NcplaneHandle $n --> NcfadectxHandle)
	is native(&core-lib) is export { * }

sub ncfadectx_iterations(NcfadectxHandle $nctx --> int32)
	is native(&core-lib) is export { * }

sub ncfadectx_free(NcfadectxHandle $nctx)
	is native(&core-lib) is export { * }

# === Metric formatting ===
# uintmax_t maps to uint64 on 64-bit platforms
# buf must be a pre-allocated char buffer (CArray[uint8])
#
# These return a pointer INTO the caller's $buf (not malloc'd). The
# returned Str must not be freed; it shares lifetime with $buf. Bind as
# Pointer and wrap with `borrowed-str-from-pointer` so NativeCall
# doesn't auto-decode-and-leak (or worse: decode-and-double-free if
# someone runs $buf through Str-typed slots).

sub _ncnmetric_raw(uint64 $val, size_t $s, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec, uint64 $mult, int32 $uprefix --> Pointer)
	is native(&core-lib) is symbol('ncnmetric') { * }

sub ncnmetric(uint64 $val, size_t $s, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec, uint64 $mult, int32 $uprefix --> Str) is export {
	borrowed-str-from-pointer(_ncnmetric_raw($val, $s, $decimal, $buf, $omitdec, $mult, $uprefix))
}

sub _ncqprefix_raw(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Pointer)
	is native(&ffi-lib) is symbol('ncqprefix') { * }

sub ncqprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str) is export {
	borrowed-str-from-pointer(_ncqprefix_raw($val, $decimal, $buf, $omitdec))
}

sub _nciprefix_raw(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Pointer)
	is native(&ffi-lib) is symbol('nciprefix') { * }

sub nciprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str) is export {
	borrowed-str-from-pointer(_nciprefix_raw($val, $decimal, $buf, $omitdec))
}

sub _ncbprefix_raw(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Pointer)
	is native(&ffi-lib) is symbol('ncbprefix') { * }

sub ncbprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str) is export {
	borrowed-str-from-pointer(_ncbprefix_raw($val, $decimal, $buf, $omitdec))
}

# === Default colors ===

sub notcurses_default_foreground(NotcursesHandle $nc, uint32 $fg is rw --> int32)
	is native(&core-lib) is export { * }

sub notcurses_default_background(NotcursesHandle $nc, uint32 $bg is rw --> int32)
	is native(&core-lib) is export { * }

# === System info ===
# All three return heap-allocated strings the caller must free.

sub _notcurses_accountname_raw( --> Pointer)
	is native(&core-lib) is symbol('notcurses_accountname') { * }

sub notcurses_accountname( --> Str) is export {
	strdup-copy-and-free(_notcurses_accountname_raw())
}

sub _notcurses_hostname_raw( --> Pointer)
	is native(&core-lib) is symbol('notcurses_hostname') { * }

sub notcurses_hostname( --> Str) is export {
	strdup-copy-and-free(_notcurses_hostname_raw())
}

sub _notcurses_osversion_raw( --> Pointer)
	is native(&core-lib) is symbol('notcurses_osversion') { * }

sub notcurses_osversion( --> Str) is export {
	strdup-copy-and-free(_notcurses_osversion_raw())
}

# === Debug ===
# debugfp is FILE*
sub notcurses_debug(NotcursesHandle $nc, Pointer $debugfp)
	is native(&core-lib) is export { * }
