use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Direct;

# 69 bindings — ncdirect_* direct mode API

# === Init/stop ===

sub ncdirect_init(Str $termtype, Pointer $fp, uint64 $flags --> NcdirectHandle)
	is native($nc-lib) is export { * }

sub ncdirect_core_init(Str $termtype, Pointer $fp, uint64 $flags --> NcdirectHandle)
	is native($core-lib) is export { * }

sub ncdirect_stop(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

# === Colors ===

sub ncdirect_set_fg_rgb(NcdirectHandle $nc, uint32 $rgb --> int32)
	is native($core-lib) is export { * }

sub ncdirect_set_bg_rgb(NcdirectHandle $nc, uint32 $rgb --> int32)
	is native($core-lib) is export { * }

sub ncdirect_set_fg_rgb8(NcdirectHandle $nc, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncdirect_set_bg_rgb8(NcdirectHandle $nc, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncdirect_set_fg_palindex(NcdirectHandle $nc, int32 $pidx --> int32)
	is native($core-lib) is export { * }

sub ncdirect_set_bg_palindex(NcdirectHandle $nc, int32 $pidx --> int32)
	is native($core-lib) is export { * }

sub ncdirect_set_fg_default(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

sub ncdirect_set_bg_default(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

sub ncdirect_palette_size(NcdirectHandle $nc --> uint32)
	is native($core-lib) is export { * }

# === Output ===

sub ncdirect_putstr(NcdirectHandle $nc, uint64 $channels, Str $utf8 --> int32)
	is native($core-lib) is export { * }

sub ncdirect_putegc(NcdirectHandle $nc, uint64 $channels, Str $utf8, int32 $sbytes is rw --> int32)
	is native($core-lib) is export { * }

sub ncdirect_flush(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

sub ncdirect_readline(NcdirectHandle $nc, Str $prompt --> Str)
	is native($core-lib) is export { * }

# === Printf (variadic) ===

sub ncdirect_printf_aligned(NcdirectHandle $n, int32 $y, int32 $align, Str $fmt, **@args --> int32)
	is native($core-lib) is export { * }

# === Dimensions ===

sub ncdirect_dim_x(NcdirectHandle $nc --> uint32)
	is native($core-lib) is export { * }

sub ncdirect_dim_y(NcdirectHandle $nc --> uint32)
	is native($core-lib) is export { * }

# === Styles ===

sub ncdirect_supported_styles(NcdirectHandle $nc --> uint16)
	is native($core-lib) is export { * }

sub ncdirect_set_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native($core-lib) is export { * }

sub ncdirect_on_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native($core-lib) is export { * }

sub ncdirect_off_styles(NcdirectHandle $n, uint32 $stylebits --> int32)
	is native($core-lib) is export { * }

sub ncdirect_styles(NcdirectHandle $n --> uint16)
	is native($core-lib) is export { * }

# === Cursor ===

sub ncdirect_cursor_move_yx(NcdirectHandle $n, int32 $y, int32 $x --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_enable(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_disable(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_up(NcdirectHandle $nc, int32 $num --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_left(NcdirectHandle $nc, int32 $num --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_right(NcdirectHandle $nc, int32 $num --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_down(NcdirectHandle $nc, int32 $num --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_yx(NcdirectHandle $n, uint32 $y is rw, uint32 $x is rw --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_push(NcdirectHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncdirect_cursor_pop(NcdirectHandle $n --> int32)
	is native($core-lib) is export { * }

# === Screen ===

sub ncdirect_clear(NcdirectHandle $nc --> int32)
	is native($core-lib) is export { * }

# === Drawing ===

# wchars is const wchar_t* — platform-specific, use Pointer
sub ncdirect_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, Pointer $wchars, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($core-lib) is export { * }

sub ncdirect_light_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncdirect_heavy_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncdirect_ascii_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncdirect_rounded_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($core-lib) is export { * }

sub ncdirect_double_box(NcdirectHandle $n, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($core-lib) is export { * }

sub ncdirect_hline_interp(NcdirectHandle $n, Str $egc, uint32 $len, uint64 $h1, uint64 $h2 --> int32)
	is native($core-lib) is export { * }

sub ncdirect_vline_interp(NcdirectHandle $n, Str $egc, uint32 $len, uint64 $h1, uint64 $h2 --> int32)
	is native($core-lib) is export { * }

# === Input ===

sub ncdirect_get(NcdirectHandle $n, Timespec $absdl, Ncinput $ni --> uint32)
	is native($core-lib) is export { * }

sub ncdirect_inputready_fd(NcdirectHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncdirect_get_nblock(NcdirectHandle $n, Ncinput $ni --> uint32)
	is native($ffi-lib) is export { * }

sub ncdirect_get_blocking(NcdirectHandle $n, Ncinput $ni --> uint32)
	is native($ffi-lib) is export { * }

# === Visual/image (ncdirectv* and ncdirectf* are opaque) ===

sub ncdirect_render_image(NcdirectHandle $n, Str $filename, int32 $align, int32 $blitter, int32 $scale --> int32)
	is native($core-lib) is export { * }

# Returns ncdirectv* (opaque rendered frame)
sub ncdirect_render_frame(NcdirectHandle $n, Str $filename, int32 $blitter, int32 $scale, int32 $maxy, int32 $maxx --> Pointer)
	is native($core-lib) is export { * }

# ncdv is ncdirectv* (opaque)
sub ncdirect_raster_frame(NcdirectHandle $n, Pointer $ncdv, int32 $align --> int32)
	is native($core-lib) is export { * }

# Returns ncdirectf* (opaque loaded frame)
sub ncdirectf_from_file(NcdirectHandle $n, Str $filename --> Pointer)
	is native($core-lib) is export { * }

# frame is ncdirectf*
sub ncdirectf_free(Pointer $frame)
	is native($core-lib) is export { * }

# frame is ncdirectf*; returns ncdirectv*
sub ncdirectf_render(NcdirectHandle $n, Pointer $frame, NcvisualOptions $vopts --> Pointer)
	is native($core-lib) is export { * }

# frame is ncdirectf*
sub ncdirectf_geom(NcdirectHandle $n, Pointer $frame, NcvisualOptions $vopts, Ncvgeom $geom --> int32)
	is native($core-lib) is export { * }

# streamer is ncstreamcb (callback), curry is void*
sub ncdirect_stream(NcdirectHandle $n, Str $filename, Pointer $streamer, NcvisualOptions $vopts, Pointer $curry --> int32)
	is native($core-lib) is export { * }

# === Capabilities ===

sub ncdirect_detected_terminal(NcdirectHandle $n --> Str)
	is native($core-lib) is export { * }

sub ncdirect_capabilities(NcdirectHandle $n --> Nccapabilities)
	is native($core-lib) is export { * }

sub ncdirect_cantruecolor(NcdirectHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canchangecolor(NcdirectHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canfade(NcdirectHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canopen_images(NcdirectHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canopen_videos(NcdirectHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canutf8(NcdirectHandle $n --> bool)
	is native($core-lib) is export { * }

sub ncdirect_check_pixel_support(NcdirectHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncdirect_canhalfblock(NcdirectHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canquadrant(NcdirectHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_cansextant(NcdirectHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canoctant(NcdirectHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canbraille(NcdirectHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub ncdirect_canget_cursor(NcdirectHandle $nc --> bool)
	is native($core-lib) is export { * }
