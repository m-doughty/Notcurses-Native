use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Plane;

# 128 bindings, 12 skipped (variadic)

sub ncplane_notcurses(NcplaneHandle $n --> NotcursesHandle)
	is native($core-lib) is export { * }

sub ncplane_notcurses_const(NcplaneHandle $n --> NotcursesHandle)
	is native($core-lib) is export { * }

sub ncplane_pixel_geom(NcplaneHandle $n, uint32 $pxy is rw, uint32 $pxx is rw, uint32 $celldimy is rw, uint32 $celldimx is rw, uint32 $maxbmapy is rw, uint32 $maxbmapx is rw)
	is native($core-lib) is export { * }

sub ncplane_resize_maximize(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_resize_marginalized(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_resize_realign(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_resize_placewithin(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_resizecb(NcplaneHandle $n, Pointer $cb)
	is native($core-lib) is export { * }

# Returns the current resize callback (function pointer)
sub ncplane_resizecb(NcplaneHandle $n --> Pointer)
	is native($core-lib) is export { * }

sub ncplane_set_name(NcplaneHandle $n, Str $name --> int32)
	is native($core-lib) is export { * }

sub ncplane_name(NcplaneHandle $n --> Str)
	is native($core-lib) is export { * }

sub ncplane_reparent(NcplaneHandle $n, NcplaneHandle $newparent --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_reparent_family(NcplaneHandle $n, NcplaneHandle $newparent --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_dup(NcplaneHandle $n, Pointer $opaque --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_translate(NcplaneHandle $src, NcplaneHandle $dst, int32 $y is rw, int32 $x is rw)
	is native($core-lib) is export { * }

sub ncplane_translate_abs(NcplaneHandle $n, int32 $y is rw, int32 $x is rw --> bool)
	is native($core-lib) is export { * }

sub ncplane_set_scrolling(NcplaneHandle $n, uint32 $scrollp --> bool)
	is native($core-lib) is export { * }

sub ncplane_scrolling_p(NcplaneHandle $n --> bool)
	is native($core-lib) is export { * }

sub ncplane_set_autogrow(NcplaneHandle $n, uint32 $growp --> bool)
	is native($core-lib) is export { * }

sub ncplane_autogrow_p(NcplaneHandle $n --> bool)
	is native($core-lib) is export { * }

sub ncplane_resize_simple(NcplaneHandle $n, uint32 $ylen, uint32 $xlen --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_set_base_cell(NcplaneHandle $n, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_base(NcplaneHandle $n, Str $egc, uint16 $stylemask, uint64 $channels --> int32)
	is native($core-lib) is export { * }

sub ncplane_base(NcplaneHandle $n, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_yx(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native($core-lib) is export { * }

sub ncplane_y(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_x(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_move_rel(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_abs_yx(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native($core-lib) is export { * }

sub ncplane_abs_y(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_abs_x(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_parent(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_parent_const(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_descendant_p(NcplaneHandle $n, NcplaneHandle $ancestor --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_move_family_above(NcplaneHandle $n, NcplaneHandle $targ --> int32)
	is native($core-lib) is export { * }

sub ncplane_move_family_below(NcplaneHandle $n, NcplaneHandle $targ --> int32)
	is native($core-lib) is export { * }

sub ncplane_move_family_top(NcplaneHandle $n)
	is native($ffi-lib) is export { * }

sub ncplane_move_family_bottom(NcplaneHandle $n)
	is native($ffi-lib) is export { * }

sub ncplane_family_destroy(Pointer $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_below(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_above(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_scrollup(NcplaneHandle $n, int32 $r --> int32)
	is native($core-lib) is export { * }

sub ncplane_scrollup_child(NcplaneHandle $n, NcplaneHandle $child --> int32)
	is native($core-lib) is export { * }

sub ncplane_rotate_cw(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_rotate_ccw(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncplane_at_cursor(NcplaneHandle $n, uint16 $stylemask is rw, uint64 $channels is rw --> Str)
	is native($core-lib) is export { * }

sub ncplane_at_cursor_cell(NcplaneHandle $n, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_at_yx(NcplaneHandle $n, int32 $y, int32 $x, uint16 $stylemask is rw, uint64 $channels is rw --> Str)
	is native($core-lib) is export { * }

sub ncplane_at_yx_cell(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_contents(NcplaneHandle $n, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx --> Str)
	is native($core-lib) is export { * }

sub ncplane_set_userptr(NcplaneHandle $n, Pointer $opaque --> Pointer)
	is native($core-lib) is export { * }

sub ncplane_userptr(NcplaneHandle $n --> Pointer)
	is native($core-lib) is export { * }

sub ncplane_center_abs(NcplaneHandle $n, int32 $y is rw, int32 $x is rw)
	is native($core-lib) is export { * }

sub ncplane_as_rgba(NcplaneHandle $n, int32 $blit, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx, uint32 $pxdimy is rw, uint32 $pxdimx is rw --> Pointer)
	is native($core-lib) is export { * }

sub ncplane_halign(NcplaneHandle $n, int32 $align, int32 $c --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_valign(NcplaneHandle $n, int32 $align, int32 $r --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_cursor_y(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_cursor_x(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_channels(NcplaneHandle $n --> uint64)
	is native($core-lib) is export { * }

sub ncplane_styles(NcplaneHandle $n --> uint16)
	is native($core-lib) is export { * }

sub ncplane_putc_yx(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_putc(NcplaneHandle $n, Nccell $c --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putchar(NcplaneHandle $n, Pointer $c --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putchar_stained(NcplaneHandle $n, Pointer $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_putegc_yx(NcplaneHandle $n, int32 $y, int32 $x, Str $gclust, Pointer $sbytes --> int32)
	is native($core-lib) is export { * }

sub ncplane_putegc(NcplaneHandle $n, Str $gclust, Pointer $sbytes --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putegc_stained(NcplaneHandle $n, Str $gclust, Pointer $sbytes --> int32)
	is native($core-lib) is export { * }

sub ncplane_putwegc(NcplaneHandle $n, Pointer $gclust, Pointer $sbytes --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwegc_yx(NcplaneHandle $n, int32 $y, int32 $x, Pointer $gclust, Pointer $sbytes --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwegc_stained(NcplaneHandle $n, Pointer $gclust, Pointer $sbytes --> int32)
	is native($core-lib) is export { * }

sub ncplane_putstr(NcplaneHandle $n, Str $gclustarr --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putstr_stained(NcplaneHandle $n, Str $gclusters --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putnstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, size_t $s, Str $str --> int32)
	is native($core-lib) is export { * }

sub ncplane_putnstr(NcplaneHandle $n, size_t $s, Str $gclustarr --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwstr_yx(NcplaneHandle $n, int32 $y, int32 $x, Pointer $gclustarr --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, Pointer $gclustarr --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwstr_stained(NcplaneHandle $n, Pointer $gclustarr --> int32)
	is native($core-lib) is export { * }

sub ncplane_putwstr(NcplaneHandle $n, Pointer $gclustarr --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_pututf32_yx(NcplaneHandle $n, int32 $y, int32 $x, uint32 $u --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwc_yx(NcplaneHandle $n, int32 $y, int32 $x, uint32 $w --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwc(NcplaneHandle $n, uint32 $w --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwc_utf32(NcplaneHandle $n, Pointer $w, uint32 $wchars is rw --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putwc_stained(NcplaneHandle $n, uint32 $w --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_puttext(NcplaneHandle $n, int32 $y, int32 $align, Str $text, Pointer $bytes --> int32)
	is native($core-lib) is export { * }

sub ncplane_hline_interp(NcplaneHandle $n, Nccell $c, uint32 $len, uint64 $c1, uint64 $c2 --> int32)
	is native($core-lib) is export { * }

sub ncplane_hline(NcplaneHandle $n, Nccell $c, uint32 $len --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_vline_interp(NcplaneHandle $n, Nccell $c, uint32 $len, uint64 $c1, uint64 $c2 --> int32)
	is native($core-lib) is export { * }

sub ncplane_vline(NcplaneHandle $n, Nccell $c, uint32 $len --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_box(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native($core-lib) is export { * }

sub ncplane_box_sized(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_perimeter(NcplaneHandle $n, Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hline, Nccell $vline, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_polyfill_yx(NcplaneHandle $n, int32 $y, int32 $x, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub ncplane_gradient(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, Str $egc, uint16 $styles, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr --> int32)
	is native($core-lib) is export { * }

sub ncplane_gradient2x1(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint32 $ul, uint32 $ur, uint32 $ll, uint32 $lr --> int32)
	is native($core-lib) is export { * }

sub ncplane_format(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint16 $stylemask --> int32)
	is native($core-lib) is export { * }

sub ncplane_stain(NcplaneHandle $n, int32 $y, int32 $x, uint32 $ylen, uint32 $xlen, uint64 $ul, uint64 $ur, uint64 $ll, uint64 $lr --> int32)
	is native($core-lib) is export { * }

sub ncplane_mergedown_simple(NcplaneHandle $src, NcplaneHandle $dst --> int32)
	is native($core-lib) is export { * }

sub ncplane_mergedown(NcplaneHandle $src, NcplaneHandle $dst, int32 $begsrcy, int32 $begsrcx, uint32 $leny, uint32 $lenx, int32 $dsty, int32 $dstx --> int32)
	is native($core-lib) is export { * }

sub ncplane_bchannel(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_fchannel(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_set_channels(NcplaneHandle $n, uint64 $channels)
	is native($core-lib) is export { * }

sub ncplane_set_bchannel(NcplaneHandle $n, uint32 $channel --> uint64)
	is native($core-lib) is export { * }

sub ncplane_set_fchannel(NcplaneHandle $n, uint32 $channel --> uint64)
	is native($core-lib) is export { * }

sub ncplane_fg_rgb(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_bg_rgb(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_fg_alpha(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_fg_default_p(NcplaneHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncplane_bg_alpha(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_bg_default_p(NcplaneHandle $n --> bool)
	is native($ffi-lib) is export { * }

sub ncplane_fg_rgb8(NcplaneHandle $n, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_bg_rgb8(NcplaneHandle $n, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_set_bg_rgb8_clipped(NcplaneHandle $n, int32 $r, int32 $g, int32 $b)
	is native($core-lib) is export { * }

sub ncplane_set_fg_rgb8_clipped(NcplaneHandle $n, int32 $r, int32 $g, int32 $b)
	is native($core-lib) is export { * }

sub ncplane_set_fg_alpha(NcplaneHandle $n, int32 $alpha --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_bg_alpha(NcplaneHandle $n, int32 $alpha --> int32)
	is native($core-lib) is export { * }

# fader is fadecb callback, curry is void*
sub ncplane_fadeout(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native($core-lib) is export { * }

sub ncplane_fadein(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native($core-lib) is export { * }

sub ncplane_fadeout_iteration(NcplaneHandle $n, NcfadectxHandle $nctx, int32 $iter, Pointer $fader, Pointer $curry --> int32)
	is native($core-lib) is export { * }

sub ncplane_fadein_iteration(NcplaneHandle $n, NcfadectxHandle $nctx, int32 $iter, Pointer $fader, Pointer $curry --> int32)
	is native($core-lib) is export { * }

sub ncplane_pulse(NcplaneHandle $n, Timespec $ts, Pointer $fader, Pointer $curry --> int32)
	is native($core-lib) is export { * }

sub ncplane_rounded_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ystop, uint32 $xstop, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_perimeter_rounded(NcplaneHandle $n, uint16 $stylemask, uint64 $channels, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_rounded_box_sized(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_double_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_ascii_box(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_perimeter_double(NcplaneHandle $n, uint16 $stylemask, uint64 $channels, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_double_box_sized(NcplaneHandle $n, uint16 $styles, uint64 $channels, uint32 $ylen, uint32 $xlen, uint32 $ctlword --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_greyscale(NcplaneHandle $n)
	is native($core-lib) is export { * }

sub ncplane_qrcode(NcplaneHandle $n, uint32 $ymax is rw, uint32 $xmax is rw, Pointer $data, size_t $len --> int32)
	is native($core-lib) is export { * }

# === Printf (variadic — requires Rakudo 2025.12+) ===

sub ncplane_printf(NcplaneHandle $n, Str $format, *@args is raw where { .all ~~ NativeCall::Types::NativelyTyped } --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_printf_yx(NcplaneHandle $n, int32 $y, int32 $x, Str $format, *@args is raw where { .all ~~ NativeCall::Types::NativelyTyped } --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_printf_aligned(NcplaneHandle $n, int32 $y, int32 $align, Str $format, *@args is raw where { .all ~~ NativeCall::Types::NativelyTyped } --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_printf_stained(NcplaneHandle $n, Str $format, *@args is raw where { .all ~~ NativeCall::Types::NativelyTyped } --> int32)
	is native($ffi-lib) is export { * }
