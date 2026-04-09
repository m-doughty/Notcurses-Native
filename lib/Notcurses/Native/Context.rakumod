use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Context;

# 55 bindings — context, pile, palette, capabilities, stats, fade, metric, utility

# === String/Unicode utilities ===

sub ncstrwidth(Str $egcs, int32 $validbytes is rw, int32 $validwidth is rw --> int32)
	is native($core-lib) is export { * }

sub notcurses_ucs32_to_utf8(CArray[uint32] $ucs32, uint32 $ucs32count, CArray[uint8] $resultbuf, size_t $buflen --> int32)
	is native($core-lib) is export { * }

sub ncwcsrtombs(CArray[int32] $src --> Str)
	is native($ffi-lib) is export { * }

# === Lex/string conversions for enums ===

sub notcurses_lex_margins(Str $op, NotcursesOptions $opts --> int32)
	is native($core-lib) is export { * }

sub notcurses_lex_blitter(Str $op, int32 $blitter is rw --> int32)
	is native($core-lib) is export { * }

sub notcurses_str_blitter(int32 $blitter --> Str)
	is native($core-lib) is export { * }

sub notcurses_lex_scalemode(Str $op, int32 $scalemode is rw --> int32)
	is native($core-lib) is export { * }

sub notcurses_str_scalemode(int32 $scalemode --> Str)
	is native($core-lib) is export { * }

# === Pile operations ===

sub ncpile_top(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncpile_bottom(NcplaneHandle $n --> NcplaneHandle)
	is native($core-lib) is export { * }

sub notcurses_top(NotcursesHandle $n --> NcplaneHandle)
	is native($ffi-lib) is export { * }

sub notcurses_bottom(NotcursesHandle $n --> NcplaneHandle)
	is native($ffi-lib) is export { * }

sub ncpile_render(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

sub ncpile_rasterize(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

# buf is char** (output), buflen is size_t* (output)
sub ncpile_render_to_buffer(NcplaneHandle $p, CArray[Pointer] $buf, CArray[size_t] $buflen --> int32)
	is native($core-lib) is export { * }

# fp is FILE*
sub ncpile_render_to_file(NcplaneHandle $p, Pointer $fp --> int32)
	is native($core-lib) is export { * }

sub ncpile_create(NotcursesHandle $nc, NcplaneOptions $nopts --> NcplaneHandle)
	is native($core-lib) is export { * }

sub notcurses_drop_planes(NotcursesHandle $nc)
	is native($core-lib) is export { * }

# === Input ===

sub notcurses_getvec(NotcursesHandle $n, Timespec $ts, Ncinput $ni, int32 $vcount --> int32)
	is native($core-lib) is export { * }

sub notcurses_inputready_fd(NotcursesHandle $n --> int32)
	is native($core-lib) is export { * }

sub notcurses_linesigs_disable(NotcursesHandle $n --> int32)
	is native($core-lib) is export { * }

sub notcurses_linesigs_enable(NotcursesHandle $n --> int32)
	is native($core-lib) is export { * }

# === Standard plane (const variant) ===

sub notcurses_stddim_yx_const(NotcursesHandle $nc, uint32 $y is rw, uint32 $x is rw --> NcplaneHandle)
	is native($ffi-lib) is export { * }

sub notcurses_at_yx(NotcursesHandle $nc, uint32 $yoff, uint32 $xoff, uint16 $stylemask is rw, uint64 $channels is rw --> Str)
	is native($core-lib) is export { * }

# === Palette ===

sub ncpalette_new(NotcursesHandle $nc --> NcpaletteHandle)
	is native($core-lib) is export { * }

sub ncpalette_use(NotcursesHandle $nc, NcpaletteHandle $p --> int32)
	is native($core-lib) is export { * }

sub ncpalette_set_rgb8(NcpaletteHandle $p, int32 $idx, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncpalette_set(NcpaletteHandle $p, int32 $idx, uint32 $rgb --> int32)
	is native($ffi-lib) is export { * }

sub ncpalette_get(NcpaletteHandle $p, int32 $idx, uint32 $palent is rw --> int32)
	is native($ffi-lib) is export { * }

sub ncpalette_get_rgb8(NcpaletteHandle $p, int32 $idx, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> int32)
	is native($ffi-lib) is export { * }

sub ncpalette_free(NcpaletteHandle $p)
	is native($core-lib) is export { * }

# === Capabilities & terminal info ===

sub notcurses_supported_styles(NotcursesHandle $nc --> uint16)
	is native($core-lib) is export { * }

sub notcurses_palette_size(NotcursesHandle $nc --> uint32)
	is native($core-lib) is export { * }

sub notcurses_detected_terminal(NotcursesHandle $nc --> Str)
	is native($core-lib) is export { * }

sub notcurses_capabilities(NotcursesHandle $n --> Nccapabilities)
	is native($core-lib) is export { * }

# Returns ncpixelimpl_e (enum as int32)
sub notcurses_check_pixel_support(NotcursesHandle $nc --> int32)
	is native($core-lib) is export { * }

sub nccapability_canchangecolor(Nccapabilities $caps --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canoctant(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

# === Statistics ===

sub notcurses_stats_alloc(NotcursesHandle $nc --> Ncstats)
	is native($core-lib) is export { * }

sub notcurses_stats(NotcursesHandle $nc, Ncstats $stats)
	is native($core-lib) is export { * }

sub notcurses_stats_reset(NotcursesHandle $nc, Ncstats $stats)
	is native($core-lib) is export { * }

# === Alignment ===

sub notcurses_align(int32 $availu, int32 $align, int32 $u --> int32)
	is native($ffi-lib) is export { * }

# === Fade context ===

sub ncfadectx_setup(NcplaneHandle $n --> NcfadectxHandle)
	is native($core-lib) is export { * }

sub ncfadectx_iterations(NcfadectxHandle $nctx --> int32)
	is native($core-lib) is export { * }

sub ncfadectx_free(NcfadectxHandle $nctx)
	is native($core-lib) is export { * }

# === Metric formatting ===
# uintmax_t maps to uint64 on 64-bit platforms
# buf must be a pre-allocated char buffer (CArray[uint8])

sub ncnmetric(uint64 $val, size_t $s, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec, uint64 $mult, int32 $uprefix --> Str)
	is native($core-lib) is export { * }

sub ncqprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str)
	is native($ffi-lib) is export { * }

sub nciprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str)
	is native($ffi-lib) is export { * }

sub ncbprefix(uint64 $val, uint64 $decimal, CArray[uint8] $buf, int32 $omitdec --> Str)
	is native($ffi-lib) is export { * }

# === Default colors ===

sub notcurses_default_foreground(NotcursesHandle $nc, uint32 $fg is rw --> int32)
	is native($core-lib) is export { * }

sub notcurses_default_background(NotcursesHandle $nc, uint32 $bg is rw --> int32)
	is native($core-lib) is export { * }

# === System info ===

sub notcurses_accountname( --> Str)
	is native($core-lib) is export { * }

sub notcurses_hostname( --> Str)
	is native($core-lib) is export { * }

sub notcurses_osversion( --> Str)
	is native($core-lib) is export { * }

# === Debug ===
# debugfp is FILE*
sub notcurses_debug(NotcursesHandle $nc, Pointer $debugfp)
	is native($core-lib) is export { * }
