use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;
use Notcurses::Native::Str :DEFAULT, :INTERNAL;

unit module Notcurses::Native::Direct;

# 69 bindings — ncdirect_* direct mode API

# === Init/stop ===

sub ncdirect_init(Str $termtype, Pointer $fp, uint64 $flags --> NcdirectHandle)
	is native(&nc-lib) is export { * }

sub ncdirect_core_init(Str $termtype, Pointer $fp, uint64 $flags --> NcdirectHandle)
	is native(&core-lib) is export { * }

sub ncdirect_stop(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

# === Colors ===

sub ncdirect_set_fg_rgb(NcdirectHandle $nc, uint32 $rgb --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_set_bg_rgb(NcdirectHandle $nc, uint32 $rgb --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_set_fg_rgb8(NcdirectHandle $nc, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native(&ffi-lib) is export { * }

sub ncdirect_set_bg_rgb8(NcdirectHandle $nc, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native(&ffi-lib) is export { * }

sub ncdirect_set_fg_palindex(NcdirectHandle $nc, int32 $pidx --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_set_bg_palindex(NcdirectHandle $nc, int32 $pidx --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_set_fg_default(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_set_bg_default(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_palette_size(NcdirectHandle $nc --> uint32)
	is native(&core-lib) is export { * }

# === Output ===

sub ncdirect_putstr(NcdirectHandle $nc, uint64 $channels, Str $utf8 --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_putegc(NcdirectHandle $nc, uint64 $channels, Str $utf8, int32 $sbytes is rw --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_flush(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

# Returns a malloc'd input line that the caller must free.
sub _ncdirect_readline_raw(NcdirectHandle $nc, Str $prompt --> Pointer)
	is native(&core-lib) is symbol('ncdirect_readline') { * }

sub ncdirect_readline(NcdirectHandle $nc, Str $prompt --> Str) is export {
	strdup-copy-and-free(_ncdirect_readline_raw($nc, $prompt))
}

# === Printf ===
#
# notcurses's ncdirect_printf_aligned is variadic, which NativeCall
# cannot call safely (see ncplane_printf in Notcurses::Native::Plane),
# and the helper its implementation leans on, ncdirect_align, is static
# in direct.c. So ncdirect_printf_aligned below is a Raku port of
# ncdirect_vprintf_aligned (direct.c), built from public calls: format,
# measure with ncstrwidth, compute the column as ncdirect_align does,
# move the cursor, write with puts(3).

# ncstrwidth with both out-parameters NULL — ncdirect_vprintf_aligned
# wants only the width. The Context binding takes them `is rw`.
sub _ncstrwidth-only(Str, Pointer, Pointer --> int32)
	is native(&core-lib) is symbol('ncstrwidth') { * }

# The C library's puts(3), which is what ncdirect_vprintf_aligned
# writes with: to the C runtime's stdout FILE*, the same stream (and
# buffer) an ncdirect opened on stdout writes its escape sequences to,
# so the text lands after the cursor move rather than racing it.
sub _c-puts(Str --> int32)
	is native(&libc-name) is symbol('puts') { * }

my constant C-EOF     = -1;
my constant C-INT-MAX = 2147483647;

# ncdirect_align (static in direct.c): the column at which text $cols
# columns wide starts under $align. Left is column 0; text wider than
# the terminal also starts at 0; an alignment other than left, centre
# or right answers INT_MAX, as in C.
my sub ncdirect-align-column(NcdirectHandle $n, Int $align, Int $cols --> Int) {
	return 0 if $align == NCALIGN_LEFT;
	my Int $dimx = ncdirect_dim_x($n);
	return 0 if $cols > $dimx;
	return ($dimx - $cols) div 2 if $align == NCALIGN_CENTER;
	return $dimx - $cols if $align == NCALIGN_RIGHT;
	C-INT-MAX
}

#|( Format C<@args> with the printf-style C<$format>, move the cursor to
    row C<$y> (-1 keeps the current row) at the column C<$align> calls for
    (C<NCALIGN_LEFT>, C<NCALIGN_CENTER> or C<NCALIGN_RIGHT>, measured in
    columns against C<ncdirect_dim_x>), and write the text followed by a
    newline. Format rules are those of C<ncplane_printf> (see C<c-sprintf>
    in Notcurses::Native::Str): C formats work unchanged, C<%n>, C<%p>
    and the wide-character conversions die, and widths count characters.

    Behaves as notcurses's own C<ncdirect_printf_aligned>, which it
    reimplements from public calls because the C function is variadic
    (NativeCall cannot call it safely — a call with no arguments after
    the format died before 0.6.7). Like the C function, it writes with
    C<puts(3)>, i.e. to the process's C C<stdout> whichever stream the
    ncdirect was opened on, and answers what C<puts> answers: a
    non-negative number on success, whose exact value is the C
    library's choice (glibc: the bytes written plus one; macOS: 10;
    Windows: 0). Answers -1, writing nothing, when the text has no
    column width (ncstrwidth rejects it: a control character, say) or
    the cursor cannot be moved, and -1 when C<puts> fails. An C<$align>
    that is none of the three asks for column C<INT_MAX>, exactly as the
    C function does, and what the terminal makes of that is up to the
    terminal: pass one of the three. Dies on an undefined handle.

        ncdirect_printf_aligned($nc, -1, NCALIGN_CENTER, "%s v%s", $name, $version); )
sub ncdirect_printf_aligned(NcdirectHandle $n, Int:D $y, Int:D $align,
	Str:D $fmt, *@args --> Int) is export
{
	die 'ncdirect_printf_aligned: the ncdirect handle is undefined' without $n;
	my Str $text = c-sprintf($fmt, @args, :caller<ncdirect_printf_aligned>);
	my Int $cols = _ncstrwidth-only($text, Pointer, Pointer);
	return -1 if $cols < 0;
	my Int $x = ncdirect-align-column($n, $align, $cols);
	return -1 if ncdirect_cursor_move_yx($n, $y, $x) != 0;
	my Int $written = _c-puts($text);
	$written == C-EOF ?? -1 !! $written
}

# === Dimensions ===

sub ncdirect_dim_x(NcdirectHandle $nc --> uint32)
	is native(&core-lib) is export { * }

sub ncdirect_dim_y(NcdirectHandle $nc --> uint32)
	is native(&core-lib) is export { * }

# === Styles ===

sub ncdirect_supported_styles(NcdirectHandle $nc --> uint16)
	is native(&core-lib) is export { * }

sub ncdirect_set_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_on_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_off_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_styles(NcdirectHandle $n --> uint16)
	is native(&core-lib) is export { * }

# === Cursor ===

sub ncdirect_cursor_move_yx(NcdirectHandle $n, int32 $y, int32 $x --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_enable(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_disable(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_up(NcdirectHandle $nc, int32 $num --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_left(NcdirectHandle $nc, int32 $num --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_right(NcdirectHandle $nc, int32 $num --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_down(NcdirectHandle $nc, int32 $num --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_yx(NcdirectHandle $n, uint32 $y is rw, uint32 $x is rw --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_push(NcdirectHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_cursor_pop(NcdirectHandle $n --> int32)
	is native(&core-lib) is export { * }

# === Screen ===

sub ncdirect_clear(NcdirectHandle $nc --> int32)
	is native(&core-lib) is export { * }

# === Drawing ===

# wchars is const wchar_t* — platform-specific, use Pointer
sub ncdirect_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, Pointer $wchars, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_light_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncdirect_heavy_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncdirect_ascii_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&ffi-lib) is export { * }

sub ncdirect_rounded_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_double_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_hline_interp(NcdirectHandle $n, Str $egc, uint32 $len, uint64 $h1, uint64 $h2 --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_vline_interp(NcdirectHandle $n, Str $egc, uint32 $len, uint64 $h1, uint64 $h2 --> int32)
	is native(&core-lib) is export { * }

# === Input ===

sub ncdirect_get(NcdirectHandle $n, Timespec $absdl, Ncinput $ni --> uint32)
	is native(&core-lib) is export { * }

sub ncdirect_inputready_fd(NcdirectHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_get_nblock(NcdirectHandle $n, Ncinput $ni --> uint32)
	is native(&ffi-lib) is export { * }

sub ncdirect_get_blocking(NcdirectHandle $n, Ncinput $ni --> uint32)
	is native(&ffi-lib) is export { * }

# === Visual/image (ncdirectv* and ncdirectf* are opaque) ===

sub ncdirect_render_image(NcdirectHandle $n, Str $filename, int32 $align, int32 $blitter, int32 $scale --> int32)
	is native(&core-lib) is export { * }

# Returns ncdirectv* (opaque rendered frame)
sub ncdirect_render_frame(NcdirectHandle $n, Str $filename, int32 $blitter, int32 $scale, int32 $maxy, int32 $maxx --> Pointer)
	is native(&core-lib) is export { * }

# ncdv is ncdirectv* (opaque)
sub ncdirect_raster_frame(NcdirectHandle $n, Pointer $ncdv, int32 $align --> int32)
	is native(&core-lib) is export { * }

# Returns ncdirectf* (opaque loaded frame)
sub ncdirectf_from_file(NcdirectHandle $n, Str $filename --> Pointer)
	is native(&core-lib) is export { * }

# frame is ncdirectf*
sub ncdirectf_free(Pointer $frame)
	is native(&core-lib) is export { * }

# frame is ncdirectf*; returns ncdirectv*
sub ncdirectf_render(NcdirectHandle $n, Pointer $frame, NcvisualOptions $vopts --> Pointer)
	is native(&core-lib) is export { * }

# frame is ncdirectf*
sub ncdirectf_geom(NcdirectHandle $n, Pointer $frame, NcvisualOptions $vopts, Ncvgeom $geom --> int32)
	is native(&core-lib) is export { * }

# streamer is ncstreamcb (callback), curry is void*
sub ncdirect_stream(NcdirectHandle $n, Str $filename, Pointer $streamer, NcvisualOptions $vopts, Pointer $curry --> int32)
	is native(&core-lib) is export { * }

# === Capabilities ===

# Returns a malloc'd terminal name that the caller must free.
sub _ncdirect_detected_terminal_raw(NcdirectHandle $n --> Pointer)
	is native(&core-lib) is symbol('ncdirect_detected_terminal') { * }

sub ncdirect_detected_terminal(NcdirectHandle $n --> Str) is export {
	strdup-copy-and-free(_ncdirect_detected_terminal_raw($n))
}

sub ncdirect_capabilities(NcdirectHandle $n --> Nccapabilities)
	is native(&core-lib) is export { * }

sub ncdirect_cantruecolor(NcdirectHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canchangecolor(NcdirectHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canfade(NcdirectHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canopen_images(NcdirectHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canopen_videos(NcdirectHandle $n --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canutf8(NcdirectHandle $n --> bool)
	is native(&core-lib) is export { * }

sub ncdirect_check_pixel_support(NcdirectHandle $n --> int32)
	is native(&core-lib) is export { * }

sub ncdirect_canhalfblock(NcdirectHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canquadrant(NcdirectHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_cansextant(NcdirectHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canoctant(NcdirectHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canbraille(NcdirectHandle $nc --> bool)
	is native(&ffi-lib) is export { * }

sub ncdirect_canget_cursor(NcdirectHandle $nc --> bool)
	is native(&core-lib) is export { * }
