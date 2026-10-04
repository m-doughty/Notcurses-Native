use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;
use Notcurses::Native::Str :DEFAULT, :INTERNAL;

unit module Notcurses::Native::Plane;

# 128 bindings. The printf family is implemented in Raku (see the
# foot of this file): notcurses's versions are variadic.

#|( Batched per-cell copy from C<$src> to C<$dst>: copies a
    C<$rows × $cols> rectangle starting at (src-y, src-x) in the
    source plane to (dst-y, dst-x) in the destination, substituting
    the source plane's base cell when the source cell has an empty
    glyph (matches notcurses's own C<ncplane_at_yx> behaviour).

    This is the C-side port of Selkie::Widget::ViewportedCardList's
    historical Raku per-cell merge loop. ncplane_mergedown looks
    like a one-call replacement but composites at absolute pile
    coordinates (not at the scroll-translated dst we need), so the
    actual loop has to live somewhere — putting it in C avoids
    paying the Raku NativeCall tax 5+ times per cell. For a typical
    chat with 5 visible cards × 5 widget planes × ~3000 cells, that
    drops ~75,000 NativeCall trips per render to one.

    Lives in C<libnotcurses_native_shim>, compiled by
    Build.rakumod's !try-compile-shim (see that method's docs for
    when this lib exists vs. when callers must fall back). Returns
    0 on success; negative results from C<ncplane_at_yx_cell>
    (cells out of bounds) are skipped silently same as the Raku
    loop did. Returns -1 only if copying a grapheme cluster longer
    than 127 bytes needs memory that cannot be allocated (cells
    already copied stay copied). C<$src> and C<$dst> may be the
    same plane.

    Every cluster is copied into shim-owned memory before the next
    notcurses call, so nothing is read through a pointer into an
    egcpool that the copy itself may have grown. Shims built before
    0.6.7 held such pointers — the source's base-cell cluster for
    the whole copy, and each cell's cluster across its own write
    when C<$src> and C<$dst> are the same plane — and read freed
    memory once the pool grew; t/37 and xxt/01-asan-copy-cells pin
    the fix. Call C<ensure-shim-loadable> before the first call in
    a process. )
sub notcurses_native_copy_cells(
    NcplaneHandle $src,
    NcplaneHandle $dst,
    int32 $src-y, int32 $src-x,
    int32 $dst-y, int32 $dst-x,
    uint32 $rows, uint32 $cols
    --> int32
)
    is native(&shim-lib) is export { * }

#|( Reserve process-wide ownership of the terminal restore guard for
    C<$owner-token>. Tokens are caller-generated, process-unique,
    non-zero unsigned 61-bit values; the shim rejects zero and values
    outside that packed-state range. Holding this reservation before capturing
    terminal state prevents a second terminal owner from replacing or
    disarming the first owner's guard. )
sub notcurses_native_reserve_terminal_guard(uint64 $owner-token --> int32)
    is native(&shim-lib) is export { * }

#|( Arm the C-level terminal restore guard for C<$owner-token>, and
    hand it the escape sequence to write on the way out.

    Call this only after C<notcurses_native_reserve_terminal_guard>
    succeeds for the same token, and while the terminal is still in
    the state you want back. Repeated arms by the same already armed
    owner are idempotent: the shim does not re-capture a terminal that
    may already be raw.

    The shim publishes a complete immutable snapshot with an atomic
    state transition. The C<atexit(3)> handler never waits on a mutex;
    it atomically claims the published snapshot and then restores only
    that snapshot. Disarm/release/rearm cannot overwrite or close the
    snapshot after the exit handler has claimed it. On Windows the
    snapshot owns duplicated console handles; on POSIX it owns an open
    C</dev/tty> fd used for bounded nonblocking cleanup output.

    The point is the exit path Raku cannot see. An END phaser, a
    C<LEAVE>, or a signal tap needs a live VM. A MoarVM panic
    (C<Heap corruption detected: ...>) calls C C<exit(3)> directly,
    so no Raku cleanup runs. A C C<atexit> handler still runs there.

    What it cannot catch, by construction:

    =item C<SIGSEGV> / C<SIGBUS> / C<SIGILL> and other synchronous fatal
        signals — Raku taps cannot guarantee execution there, and the
        kernel can end the process without running C<atexit> handlers.
    =item C<SIGKILL> — same, and uncatchable anyway.
    =item C<_exit(2)>, C<_Exit(3)>, C<abort(3)> — all skip C<atexit>.
    =item Crashes inside C<notcurses_stop> itself. This guard is not a
        fix for core notcurses shutdown bugs.

    Returns 0 when armed. Non-zero means nothing new was armed: 1 null
    cleanup, 2 cleanup longer than 1024 bytes, 3 no terminal, 4 state
    unreadable, 5 C<atexit> refused, 6 another owner holds or is
    exiting the guard, 7 token mismatch, 8 invalid token. )
sub notcurses_native_arm_terminal_guard_owned(uint64 $owner-token, Str $cleanup --> int32)
    is native(&shim-lib) is export { * }

#|( Disarm the guard only if C<$owner-token> is the current owner. The
    owner reservation remains held. Returns 0 on success, 6 if the
    exit handler has already claimed the snapshot, 7 for an owner
    mismatch, and 8 for an invalid token. )
sub notcurses_native_disarm_terminal_guard_owned(uint64 $owner-token --> int32)
    is native(&shim-lib) is export { * }

#|( Release C<$owner-token>'s reservation. This also disarms and closes
    any unclaimed snapshot for that owner. A non-zero return means the
    reservation was not released; a caller must not assume another TUI
    may now take ownership. )
sub notcurses_native_release_terminal_guard(uint64 $owner-token --> int32)
    is native(&shim-lib) is export { * }

#|( Compatibility wrapper around the owned API. It uses an internal
    legacy owner token, so it returns 6 if a tokenized owner has
    already reserved the guard. New terminal owners should use the
    reserve/owned-arm/release calls above. )
sub notcurses_native_arm_terminal_guard(Str $cleanup --> int32)
    is native(&shim-lib) is export { * }

#|( Compatibility release for the internal legacy owner token. It will
    not disarm a tokenized owner. New code should call
    C<notcurses_native_release_terminal_guard>. )
sub notcurses_native_disarm_terminal_guard()
    is native(&shim-lib) is export { * }

sub ncplane_notcurses(NcplaneHandle $n --> NotcursesHandle)
	is native(&core-lib) is export { * }

sub ncplane_notcurses_const(NcplaneHandle $n --> NotcursesHandle)
	is native(&core-lib) is export { * }

sub ncplane_pixel_geom(NcplaneHandle $n, uint32 $pxy is rw, uint32 $pxx is rw, uint32 $celldimy is rw, uint32 $celldimx is rw, uint32 $maxbmapy is rw, uint32 $maxbmapx is rw)
	is native(&core-lib) is export { * }

sub ncplane_resize_maximize(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_resize_marginalized(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_resize_realign(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_resize_placewithin(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_resizecb(NcplaneHandle $n, Pointer $cb)
	is native(&core-lib) is export { * }

# Returns the current resize callback (function pointer)
sub ncplane_resizecb(NcplaneHandle $n --> Pointer)
	is native(&core-lib) is export { * }

sub ncplane_set_name(NcplaneHandle $n, Str $name --> int32)
	is native(&core-lib) is export { * }

# notcurses strdups the name (notcurses.h: "Return a heap-allocated copy of
# the plane's name"), so the pointer is the caller's to free. Bound raw and
# wrapped below; a `--> Str` binding decodes the bytes and leaks the copy.
sub _ncplane_name_raw(NcplaneHandle $n --> Pointer)
	is native(&core-lib) is symbol('ncplane_name') { * }

#|( The plane's name as a Raku-owned C<Str>. A plane created without a
    name answers C<''> (notcurses stores an empty name); one whose name
    was cleared with C<ncplane_set_name($n, Str)> answers the C<Str>
    type object. notcurses returns a heap copy of the name; this wrapper
    decodes it and frees the copy, so there is nothing for the caller to
    release. Before 0.6.7 this was bound directly as C«--> Str» on the
    belief that the pointer was library-owned, and every call leaked the
    copy. )
sub ncplane_name(NcplaneHandle $n --> Str) is export {
	strdup-copy-and-free(_ncplane_name_raw($n))
}

sub ncplane_reparent(NcplaneHandle $n, NcplaneHandle $newparent --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_reparent_family(NcplaneHandle $n, NcplaneHandle $newparent --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_dup(NcplaneHandle $n, Pointer $opaque --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_translate(NcplaneHandle $src, NcplaneHandle $dst, int32 $y is rw, int32 $x is rw)
	is native(&core-lib) is export { * }

sub ncplane_translate_abs(NcplaneHandle $n, int32 $y is rw, int32 $x is rw --> bool)
	is native(&core-lib) is export { * }

sub ncplane_set_scrolling(NcplaneHandle $n, uint32 $scrollp --> bool)
	is native(&core-lib) is export { * }

sub ncplane_scrolling_p(NcplaneHandle $n --> bool)
	is native(&core-lib) is export { * }

sub ncplane_set_autogrow(NcplaneHandle $n, uint32 $growp --> bool)
	is native(&core-lib) is export { * }

sub ncplane_autogrow_p(NcplaneHandle $n --> bool)
	is native(&core-lib) is export { * }

sub ncplane_resize_simple(NcplaneHandle $n, uint32 $ylen, uint32 $xlen --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_set_base_cell(NcplaneHandle $n, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_base(NcplaneHandle $n, Str $egc, uint16 $stylemask, uint64 $channels --> int32)
	is native(&core-lib) is export { * }

sub ncplane_base(NcplaneHandle $n, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub ncplane_yx(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native(&core-lib) is export { * }

sub ncplane_y(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_x(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_move_rel(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_abs_yx(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native(&core-lib) is export { * }

sub ncplane_abs_y(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_abs_x(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_parent(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_parent_const(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_descendant_p(NcplaneHandle $n, NcplaneHandle $ancestor --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_move_family_above(NcplaneHandle $n, NcplaneHandle $targ --> int32)
	is native(&core-lib) is export { * }

sub ncplane_move_family_below(NcplaneHandle $n, NcplaneHandle $targ --> int32)
	is native(&core-lib) is export { * }

sub ncplane_move_family_top(NcplaneHandle $n)
	is native(&ffi-lib) is export { * }

sub ncplane_move_family_bottom(NcplaneHandle $n)
	is native(&ffi-lib) is export { * }

sub ncplane_family_destroy(Pointer $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_below(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_above(NcplaneHandle $n --> NcplaneHandle)
	is native(&core-lib) is export { * }

sub ncplane_scrollup(NcplaneHandle $n, int32 $r --> int32)
	is native(&core-lib) is export { * }

sub ncplane_scrollup_child(NcplaneHandle $n, NcplaneHandle $child --> int32)
	is native(&core-lib) is export { * }

sub ncplane_rotate_cw(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncplane_rotate_ccw(NcplaneHandle $n --> int32)
	is native(&core-lib) is export { * }

# ncplane_at_cursor / at_yx / contents all return heap-allocated EGC
# strings the caller must free.

sub _ncplane_at_cursor_raw(NcplaneHandle $n, uint16 $stylemask is rw, uint64 $channels is rw --> Pointer)
	is native(&core-lib) is symbol('ncplane_at_cursor') { * }

sub ncplane_at_cursor(NcplaneHandle $n, uint16 $stylemask is rw, uint64 $channels is rw --> Str) is export {
	strdup-copy-and-free(_ncplane_at_cursor_raw($n, $stylemask, $channels))
}

sub ncplane_at_cursor_cell(NcplaneHandle $n, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub _ncplane_at_yx_raw(NcplaneHandle $n, int32 $y, int32 $x, uint16 $stylemask is rw, uint64 $channels is rw --> Pointer)
	is native(&core-lib) is symbol('ncplane_at_yx') { * }

sub ncplane_at_yx(NcplaneHandle $n, int32 $y, int32 $x, uint16 $stylemask is rw, uint64 $channels is rw --> Str) is export {
	strdup-copy-and-free(_ncplane_at_yx_raw($n, $y, $x, $stylemask, $channels))
}

sub ncplane_at_yx_cell(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub _ncplane_contents_raw(NcplaneHandle $n, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx --> Pointer)
	is native(&core-lib) is symbol('ncplane_contents') { * }

sub ncplane_contents(NcplaneHandle $n, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx --> Str) is export {
	strdup-copy-and-free(_ncplane_contents_raw($n, $begy, $begx, $leny, $lenx))
}

sub ncplane_set_userptr(NcplaneHandle $n, Pointer $opaque --> Pointer)
	is native(&core-lib) is export { * }

sub ncplane_userptr(NcplaneHandle $n --> Pointer)
	is native(&core-lib) is export { * }

sub ncplane_center_abs(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native(&core-lib) is export { * }

#|( Raw binding. Rasterises a region of the plane into RGBA pixels as the
    given blitter would draw it, writing the pixel geometry to C<$pxdimy>
    and C<$pxdimx> and answering a C<malloc(3)>'d array of
    C<$pxdimy × $pxdimx> 32-bit pixels, or a NULL C<Pointer> on failure
    (notcurses may set the dimensions before failing, so test the pointer,
    not the dimensions). CALLER FREES the array with C<c-free>. Prefer
    C<ncplane-as-rgba>, which copies the pixels into a Raku-owned
    C<buf32> and frees the array itself. )
sub ncplane_as_rgba(NcplaneHandle $n, int32 $blit, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx, uint32 $pxdimy is rw, uint32 $pxdimx is rw --> Pointer)
	is native(&core-lib) is export { * }

#|( Rasterise a region of the plane into RGBA pixels and answer them as a
    Raku-owned C<buf32> holding C<$pxdimy × $pxdimx> pixels in row-major
    order, each in notcurses's C<ncpixel> layout (red in the low byte,
    alpha in the high byte). C<$pxdimy> and C<$pxdimx> receive the pixel
    geometry, exactly as for C<ncplane_as_rgba>; C<$blit> must be a
    concrete cell blitter (not C<NCBLIT_DEFAULT>, not C<NCBLIT_PIXEL>),
    and a C<$leny> / C<$lenx> of 0 means "to the plane's edge".

    notcurses allocates the pixel array; this wrapper copies it and frees
    the original before returning, so there is nothing for the caller to
    release. Answers the C<buf32> type object when notcurses refuses the
    request (bad geometry, an unsupported blitter, or a cell glyph the
    blitter has no pixel pattern for), and — with 0 for both dimensions,
    without calling notcurses, which would dereference it — for an
    undefined plane. )
sub ncplane-as-rgba(NcplaneHandle $n, Int $blit, Int $begy, Int $begx,
	Int $leny, Int $lenx, $pxdimy is rw, $pxdimx is rw --> buf32) is export
{
	without $n {
		$pxdimy = 0;
		$pxdimx = 0;
		return buf32;
	}
	my uint32 $rows = 0;
	my uint32 $cols = 0;
	my Pointer $pixels = ncplane_as_rgba($n, $blit, $begy, $begx,
		$leny, $lenx, $rows, $cols);
	$pxdimy = $rows;
	$pxdimx = $cols;
	return buf32 unless $pixels.defined && +$pixels;
	# Freed on every exit from here on, an exception from the copy
	# included. Two details are load-bearing. A LEAVE runs on the early
	# return above as well, hence the definedness guard. And `<>` hands
	# c-free the pointer rather than the variable: a NativeCall callsite
	# whose first call receives a type object through a Scalar container
	# passes NULL for every later call through it (Rakudo 2025.05 to
	# 2026.08 at least), which silently turned this free into a no-op —
	# every successful call leaked its pixel array once any call had
	# failed. t/38 pins that order.
	LEAVE { c-free($pixels<>) if $pixels.defined && +$pixels }
	my Int $count = $rows * $cols;
	my $out = buf32.allocate($count);
	copy-native-into-blob($out, $pixels, $count * 4);
	$out
}

sub ncplane_halign(NcplaneHandle $n, int32 $align, int32 $c --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_valign(NcplaneHandle $n, int32 $align, int32 $r --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_cursor_y(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_cursor_x(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_channels(NcplaneHandle $n --> uint64)
	is native(&core-lib) is export { * }

sub ncplane_styles(NcplaneHandle $n --> uint16)
	is native(&core-lib) is export { * }

sub ncplane_putc_yx(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putc(NcplaneHandle $n, Nccell $c --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putchar(NcplaneHandle $n, Pointer $c --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putchar_stained(NcplaneHandle $n, Pointer $c --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putegc_yx(NcplaneHandle $n, int32 $y, int32 $x, Str $gclust, Pointer $sbytes --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putegc(NcplaneHandle $n, Str $gclust, Pointer $sbytes --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putegc_stained(NcplaneHandle $n, Str $gclust, Pointer $sbytes --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putwegc(NcplaneHandle $n, Pointer $gclust, Pointer $sbytes --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwegc_yx(NcplaneHandle $n, int32 $y, int32 $x, Pointer $gclust, Pointer $sbytes --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwegc_stained(NcplaneHandle $n, Pointer $gclust, Pointer $sbytes --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putstr(NcplaneHandle $n, Str $gclustarr --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putstr_stained(NcplaneHandle $n, Str $gclusters --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putnstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, size_t $s, Str $str --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putnstr(NcplaneHandle $n, size_t $s, Str $gclustarr --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwstr_yx(NcplaneHandle $n, int32 $y, int32 $x, Pointer $gclustarr --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, Pointer $gclustarr --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwstr_stained(NcplaneHandle $n, Pointer $gclustarr --> int32)
	is native(&core-lib) is export { * }

sub ncplane_putwstr(NcplaneHandle $n, Pointer $gclustarr --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_pututf32_yx(NcplaneHandle $n, int32 $y, int32 $x, uint32 $u --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwc_yx(NcplaneHandle $n, int32 $y, int32 $x, uint32 $w --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwc(NcplaneHandle $n, uint32 $w --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwc_utf32(NcplaneHandle $n, Pointer $w, uint32 $wchars is rw --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_putwc_stained(NcplaneHandle $n, uint32 $w --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_puttext(NcplaneHandle $n, int32 $y, int32 $align, Str $text, Pointer $bytes --> int32)
	is native(&core-lib) is export { * }

sub ncplane_hline_interp(NcplaneHandle $n, Nccell $c, uint32 $len, uint64 $c1, uint64 $c2 --> int32)
	is native(&core-lib) is export { * }

sub ncplane_hline(NcplaneHandle $n, Nccell $c, uint32 $len --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_vline_interp(NcplaneHandle $n, Nccell $c, uint32 $len, uint64 $c1, uint64 $c2 --> int32)
	is native(&core-lib) is export { * }

sub ncplane_vline(NcplaneHandle $n, Nccell $c, uint32 $len --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_box(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native(&core-lib) is export { * }

sub ncplane_box_sized(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_perimeter(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_polyfill_yx(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native(&core-lib) is export { * }

sub ncplane_gradient(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, Str $egc, uint16 $styles, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr --> int32)
	is native(&core-lib) is export { * }

sub ncplane_gradient2x1(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint32 $ul, uint32 $ur, uint32 $ll, uint32 $lr --> int32)
	is native(&core-lib) is export { * }

sub ncplane_format(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint16 $stylemask --> int32)
	is native(&core-lib) is export { * }

sub ncplane_stain(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr --> int32)
	is native(&core-lib) is export { * }

sub ncplane_mergedown_simple(NcplaneHandle $src, NcplaneHandle $dst --> int32)
	is native(&core-lib) is export { * }

sub ncplane_mergedown(NcplaneHandle $src, NcplaneHandle $dst, int32 $begsrcy, int32 $begsrcx, uint32 $leny, uint32 $lenx, int32 $dsty, int32 $dstx --> int32)
	is native(&core-lib) is export { * }

sub ncplane_bchannel(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_fchannel(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_set_channels(NcplaneHandle $n, uint64 $channels)
	is native(&core-lib) is export { * }

sub ncplane_set_bchannel(NcplaneHandle $n, uint32 $channel --> uint64)
	is native(&core-lib) is export { * }

sub ncplane_set_fchannel(NcplaneHandle $n, uint32 $channel --> uint64)
	is native(&core-lib) is export { * }

sub ncplane_fg_rgb(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_bg_rgb(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_fg_alpha(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_fg_default_p(NcplaneHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncplane_bg_alpha(NcplaneHandle $n --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_bg_default_p(NcplaneHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncplane_fg_rgb8(NcplaneHandle $n, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_bg_rgb8(NcplaneHandle $n, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native(&ffi-lib) is export { * }

sub ncplane_set_bg_rgb8_clipped(NcplaneHandle $n, int32 $r, int32 $g, int32 $b)
	is native(&core-lib) is export { * }

sub ncplane_set_fg_rgb8_clipped(NcplaneHandle $n, int32 $r, int32 $g, int32 $b)
	is native(&core-lib) is export { * }

sub ncplane_set_fg_alpha(NcplaneHandle $n, int32 $alpha --> int32)
	is native(&core-lib) is export { * }

sub ncplane_set_bg_alpha(NcplaneHandle $n, int32 $alpha --> int32)
	is native(&core-lib) is export { * }

# fader is fadecb callback, curry is void*
sub ncplane_fadeout(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

sub ncplane_fadein(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

sub ncplane_fadeout_iteration(NcplaneHandle $n, NcfadectxHandle $nctx, int32 $iter, Pointer $fader, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

sub ncplane_fadein_iteration(NcplaneHandle $n, NcfadectxHandle $nctx, int32 $iter, Pointer $fader, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

sub ncplane_pulse(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

sub ncplane_rounded_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_perimeter_rounded(NcplaneHandle $n, uint16 $stylemask, uint64 $channels, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_rounded_box_sized(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_double_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_ascii_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_perimeter_double(NcplaneHandle $n, uint16 $stylemask, uint64 $channels, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_double_box_sized(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncplane_greyscale(NcplaneHandle $n)
	is native(&core-lib) is export { * }

sub ncplane_qrcode(NcplaneHandle $n, uint32 $ymax is rw, uint32 $xmax is rw, Pointer $data, size_t $len --> int32)
	is native(&core-lib) is export { * }

# === Printf ===
#
# notcurses's printf family is variadic, and NativeCall cannot call a C
# variadic function safely: a call with no variadic arguments always
# dies, and on Windows every integer or pointer vararg is passed as a
# 32-bit `long`, truncating anything wider. These four are therefore
# Raku subs that do what notcurses's own ncplane_vprintf_* do after
# formatting — format the text (here with Raku's sprintf, see
# c-sprintf in Notcurses::Native::Str for the format rules), then hand
# it to the fixed-arity putstr call the C version uses. Names, argument
# order and return values are the C functions'.

# Every printf entry point refuses an undefined plane rather than let
# the putstr call dereference NULL (notcurses declares the plane
# argument nonnull).
my sub printf-plane(NcplaneHandle $n, Str:D $caller --> Nil) {
	die "$caller: the plane handle is undefined" without $n;
}

#|( Format C<@args> with the printf-style C<$format> and write the result
    at the cursor, exactly as C<ncplane_putstr> would: answers the number
    of columns written, or a non-positive count of the columns written
    before notcurses failed (the plane's edge, say). C formats work
    unchanged — see C<c-sprintf> in Notcurses::Native::Str for the
    details: C length modifiers such as C<%lld> or C<%zu> are accepted
    and values are never truncated to them; C<%n>, C<%p> and the
    wide-character conversions die; widths and precisions count
    characters (graphemes) rather than bytes; and a format whose
    conversions do not match the arguments dies instead of printing
    garbage.

    Formatting happens in Raku, not in C: notcurses's C<ncplane_printf>
    is variadic, and NativeCall cannot call a variadic C function
    safely, so this sub never calls it. Before 0.6.7 it did — any call
    with no arguments after the format died, and on Windows 64-bit
    integers were truncated to 32 bits. Dies on an undefined plane.

        ncplane_printf($plane, "%d of %d", $done, $total);
        ncplane_printf($plane, "%-12s|%5.1f%%", $label, $percent);
        ncplane_printf($plane, "no arguments at all");  # fine )
sub ncplane_printf(NcplaneHandle $n, Str:D $format, *@args --> Int) is export {
	printf-plane($n, 'ncplane_printf');
	ncplane_putstr_yx($n, -1, -1,
		c-sprintf($format, @args, :caller<ncplane_printf>))
}

#|( C<ncplane_printf> at row C<$y>, column C<$x> (either may be -1 to keep
    the cursor's row or column). Answers what C<ncplane_putstr_yx> answers
    for the formatted text: the columns written, or a non-positive count
    of the columns written before a failure. Same format rules as
    C<ncplane_printf>.

        ncplane_printf_yx($plane, 0, 0, "%s: %lld bytes", $name, $size); )
sub ncplane_printf_yx(NcplaneHandle $n, Int:D $y, Int:D $x, Str:D $format,
	*@args --> Int) is export
{
	printf-plane($n, 'ncplane_printf_yx');
	ncplane_putstr_yx($n, $y, $x,
		c-sprintf($format, @args, :caller<ncplane_printf_yx>))
}

#|( C<ncplane_printf> on row C<$y>, placed horizontally by C<$align>
    (C<NCALIGN_LEFT>, C<NCALIGN_CENTER> or C<NCALIGN_RIGHT>) the way
    C<ncplane_putstr_aligned> places a string: by its width in columns,
    starting at column 0 when the text is wider than the plane. Answers
    what C<ncplane_putstr_aligned> answers. Same format rules as
    C<ncplane_printf>.

        ncplane_printf_aligned($plane, 0, NCALIGN_CENTER, "Page %d/%d", $page, $pages); )
sub ncplane_printf_aligned(NcplaneHandle $n, Int:D $y, Int:D $align,
	Str:D $format, *@args --> Int) is export
{
	printf-plane($n, 'ncplane_printf_aligned');
	ncplane_putstr_aligned($n, $y, $align,
		c-sprintf($format, @args, :caller<ncplane_printf_aligned>))
}

#|( C<ncplane_printf> that replaces the glyphs at the cursor but keeps the
    styling and colours already in those cells, as C<ncplane_putstr_stained>
    does. Answers what C<ncplane_putstr_stained> answers. Same format
    rules as C<ncplane_printf>.

        ncplane_cursor_move_yx($plane, 2, 0);
        ncplane_printf_stained($plane, "%3d%%", $percent);  # recolour-free update )
sub ncplane_printf_stained(NcplaneHandle $n, Str:D $format, *@args --> Int)
	is export
{
	printf-plane($n, 'ncplane_printf_stained');
	ncplane_putstr_stained($n,
		c-sprintf($format, @args, :caller<ncplane_printf_stained>))
}
