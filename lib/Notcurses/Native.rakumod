use NativeCall;
use Notcurses::Native::Types;

unit module Notcurses::Native;

# === Library paths ===
# We load three notcurses libs: core (init, context, plane, channels),
# full (adds multimedia/image via ffmpeg), and ffi (C wrappers for
# static-inline functions). NativeCall picks the right one per binding.
#
# Lookup precedence (per library):
#   1. $NOTCURSES_NATIVE_LIB_DIR env var — explicit override. Full
#      path to a directory containing all three libs. Escape hatch
#      for custom notcurses builds; you take responsibility for ABI.
#   2. %?RESOURCES — staged at install time by Build.rakumod from
#      either a prebuilt GitHub release or a local CMake compile.

constant $os is export = $*KERNEL.name.lc;
constant $ext is export = $os ~~ /darwin/ ?? 'dylib'
                       !! $*DISTRO.is-win ?? 'dll'
                       !! 'so';

sub _lib-in-dir(Str $dir, Str $name --> Str) {
    my $path = "$dir/$name.$ext".IO;
    return $path.Str if $path.e;
    # Some distros ship versioned sibling names (libnotcurses.3.dylib,
    # libnotcurses.so.3). Walk the dir looking for any variant of
    # <name>.<ext>; matches `name.ext`, `name-N.ext`, `name.N.ext`,
    # `name.ext.N`, `name.ext.N.M.K`.
    for $path.parent.dir -> $entry {
        next unless $entry.f;
        my $bn = $entry.basename;
        return $entry.Str if $bn eq "$name.$ext";
        return $entry.Str if $bn.starts-with("$name.") && $bn.contains(".$ext");
        return $entry.Str if $bn.starts-with("$name-") && $bn.ends-with(".$ext");
    }
    Str;
}

sub _resolve-lib(Str $name --> Str) {
    with %*ENV<NOTCURSES_NATIVE_LIB_DIR> -> $override-dir {
        if $override-dir.chars && $override-dir.IO.d {
            with _lib-in-dir($override-dir, $name) -> $path {
                return $path;
            }
        }
    }
    %?RESOURCES{"lib/$name.{$ext}"}.IO.Str;
}

sub _nc-lib   { _resolve-lib('libnotcurses')      }
sub _ffi-lib  { _resolve-lib('libnotcurses-ffi')  }
sub _core-lib { _resolve-lib('libnotcurses-core') }

constant $nc-lib is export   = _nc-lib();
constant $ffi-lib is export  = _ffi-lib();
constant $core-lib is export = _core-lib();

# === Version ===

sub notcurses_version(--> Str)
	is native($core-lib) is export { * }

sub notcurses_version_components(int32 $major is rw, int32 $minor is rw, int32 $patch is rw, int32 $tweak is rw)
	is native($core-lib) is export { * }

# === Context init/stop (from libnotcurses-core, re-exported by libnotcurses) ===

sub notcurses_core_init(NotcursesOptions $opts, Pointer $fp --> NotcursesHandle)
	is native($core-lib) is export { * }

sub notcurses_init(NotcursesOptions $opts, Pointer $fp --> NotcursesHandle)
	is native($nc-lib) is export { * }

sub notcurses_stop(NotcursesHandle $nc --> int32)
	is native($core-lib) is export { * }

# === Standard plane ===

sub notcurses_stdplane(NotcursesHandle $nc --> NcplaneHandle)
	is native($core-lib) is export { * }

sub notcurses_stdplane_const(NotcursesHandle $nc --> NcplaneHandle)
	is native($core-lib) is export { * }

sub notcurses_stddim_yx(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw --> NcplaneHandle)
	is native($ffi-lib) is export { * }

# === Rendering ===

sub notcurses_render(NotcursesHandle $nc --> int32)
	is native($ffi-lib) is export { * }

sub notcurses_refresh(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw --> int32)
	is native($core-lib) is export { * }

# === Terminal dimensions ===

sub notcurses_term_dim_yx(NotcursesHandle $nc, uint32 $rows is rw, uint32 $cols is rw)
	is native($ffi-lib) is export { * }

# === Capabilities ===

sub notcurses_cantruecolor(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canfade(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canchangecolor(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canopen_images(NotcursesHandle $nc --> bool)
	is native($core-lib) is export { * }

sub notcurses_canopen_videos(NotcursesHandle $nc --> bool)
	is native($core-lib) is export { * }

sub notcurses_canbraille(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_cansextant(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canpixel(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canutf8(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canhalfblock(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

sub notcurses_canquadrant(NotcursesHandle $nc --> bool)
	is native($ffi-lib) is export { * }

# === Alternate screen ===

sub notcurses_enter_alternate_screen(NotcursesHandle $nc --> int32)
	is native($core-lib) is export { * }

sub notcurses_leave_alternate_screen(NotcursesHandle $nc --> int32)
	is native($core-lib) is export { * }

# === Cursor ===

sub notcurses_cursor_enable(NotcursesHandle $nc, int32 $y, int32 $x --> int32)
	is native($core-lib) is export { * }

sub notcurses_cursor_disable(NotcursesHandle $nc --> int32)
	is native($core-lib) is export { * }

sub notcurses_cursor_yx(NotcursesHandle $nc, int32 $y is rw, int32 $x is rw --> int32)
	is native($core-lib) is export { * }

# === Input ===

sub notcurses_get(NotcursesHandle $nc, Timespec $ts, Ncinput $ni --> uint32)
	is native($core-lib) is export { * }

sub notcurses_get_nblock(NotcursesHandle $nc, Ncinput $ni --> uint32)
	is native($ffi-lib) is export { * }

sub notcurses_get_blocking(NotcursesHandle $nc, Ncinput $ni --> uint32)
	is native($ffi-lib) is export { * }

# === Mouse ===

sub notcurses_mice_enable(NotcursesHandle $nc, uint32 $eventmask --> int32)
	is native($core-lib) is export { * }

sub notcurses_mice_disable(NotcursesHandle $nc --> int32)
	is native($ffi-lib) is export { * }

# === Plane creation/destruction ===

sub ncplane_create(NcplaneHandle $parent, NcplaneOptions $opts --> NcplaneHandle)
	is native($core-lib) is export { * }

sub ncplane_destroy(NcplaneHandle $n --> int32)
	is native($core-lib) is export { * }

# === Plane dimensions ===

sub ncplane_dim_yx(NcplaneHandle $n, uint32 $rows is rw, uint32 $cols is rw)
	is native($core-lib) is export { * }

# FFI functions for inline plane helpers
sub ncplane_dim_y(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

sub ncplane_dim_x(NcplaneHandle $n --> uint32)
	is native($ffi-lib) is export { * }

# === Plane output ===

sub ncplane_putchar_yx(NcplaneHandle $n, int32 $y, int32 $x, uint8 $c --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putstr_yx(NcplaneHandle $n, int32 $y, int32 $x, Str $str --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putstr_aligned(NcplaneHandle $n, int32 $y, int32 $align, Str $str --> int32)
	is native($ffi-lib) is export { * }

sub ncplane_putnstr_yx(NcplaneHandle $n, int32 $y, int32 $x, size_t $len, Str $str --> int32)
	is native($ffi-lib) is export { * }

# === Plane cursor ===

sub ncplane_cursor_move_yx(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native($core-lib) is export { * }

sub ncplane_cursor_move_rel(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native($core-lib) is export { * }

sub ncplane_cursor_yx(NcplaneHandle $n, uint32 $y is rw, uint32 $x is rw)
	is native($core-lib) is export { * }

sub ncplane_home(NcplaneHandle $n)
	is native($core-lib) is export { * }

# === Plane styling ===

sub ncplane_set_styles(NcplaneHandle $n, uint32 $styles)
	is native($core-lib) is export { * }

sub ncplane_on_styles(NcplaneHandle $n, uint32 $styles)
	is native($core-lib) is export { * }

sub ncplane_off_styles(NcplaneHandle $n, uint32 $styles)
	is native($core-lib) is export { * }

# === Plane colors (via FFI for inline functions) ===

sub ncplane_set_fg_rgb(NcplaneHandle $n, uint32 $channel --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_bg_rgb(NcplaneHandle $n, uint32 $channel --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_fg_rgb8(NcplaneHandle $n, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_bg_rgb8(NcplaneHandle $n, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_fg_default(NcplaneHandle $n)
	is native($core-lib) is export { * }

sub ncplane_set_bg_default(NcplaneHandle $n)
	is native($core-lib) is export { * }

sub ncplane_set_fg_palindex(NcplaneHandle $n, uint32 $idx --> int32)
	is native($core-lib) is export { * }

sub ncplane_set_bg_palindex(NcplaneHandle $n, uint32 $idx --> int32)
	is native($core-lib) is export { * }

# === Plane erase ===

sub ncplane_erase(NcplaneHandle $n)
	is native($core-lib) is export { * }

sub ncplane_erase_region(NcplaneHandle $n, int32 $ystart, int32 $xstart, int32 $ylen, int32 $xlen --> int32)
	is native($core-lib) is export { * }

# === Plane movement/resize ===

sub ncplane_move_yx(NcplaneHandle $n, int32 $y, int32 $x --> int32)
	is native($core-lib) is export { * }

sub ncplane_resize(NcplaneHandle $n, int32 $keepy, int32 $keepx,
	uint32 $keepleny, uint32 $keeplenx,
	int32 $yoff, int32 $xoff,
	uint32 $ylen, uint32 $xlen --> int32)
	is native($core-lib) is export { * }

# === Plane z-order ===

sub ncplane_move_top(NcplaneHandle $n)
	is native($ffi-lib) is export { * }

sub ncplane_move_bottom(NcplaneHandle $n)
	is native($ffi-lib) is export { * }

sub ncplane_move_above(NcplaneHandle $n, NcplaneHandle $above --> int32)
	is native($core-lib) is export { * }

sub ncplane_move_below(NcplaneHandle $n, NcplaneHandle $below --> int32)
	is native($core-lib) is export { * }

# === Cell functions (FFI) ===

# === Visual (must use $nc-lib to get FFmpeg multimedia backend) ===

sub ncvisual_from_file(Str $file --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_rgba(Pointer $rgba, int32 $rows, int32 $rowstride, int32 $cols --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_destroy(NcvisualHandle $v)
	is native($nc-lib) is export { * }

sub ncvisual_decode(NcvisualHandle $v --> int32)
	is native($nc-lib) is export { * }

sub ncvisual_resize(NcvisualHandle $v, int32 $rows, int32 $cols --> int32)
	is native($nc-lib) is export { * }
