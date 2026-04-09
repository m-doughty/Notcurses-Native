use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Visual;

# 27 bindings — ncvisual_*, ncblit_* visual/image functions

# === Construction ===
# ncvisual_from_file is in Native.rakumod (core init functions)

# rgba/bgra data is raw pixel buffer (Pointer to packed bytes)
sub ncvisual_from_rgb_packed(Pointer $rgba, int32 $rows, int32 $rowstride, int32 $cols, int32 $alpha --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_rgb_loose(Pointer $rgba, int32 $rows, int32 $rowstride, int32 $cols, int32 $alpha --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_bgra(Pointer $bgra, int32 $rows, int32 $rowstride, int32 $cols --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_palidx(Pointer $data, int32 $rows, int32 $rowstride, int32 $cols, int32 $palsize, int32 $pstride, CArray[uint32] $palette --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_plane(NcplaneHandle $n, int32 $blit, int32 $begy, int32 $begx, uint32 $leny, uint32 $lenx --> NcvisualHandle)
	is native($nc-lib) is export { * }

sub ncvisual_from_sixel(Str $s, uint32 $leny, uint32 $lenx --> NcvisualHandle)
	is native($nc-lib) is export { * }

# === Decoding ===
# ncvisual_destroy and ncvisual_decode are in Native.rakumod

sub ncvisual_decode_loop(NcvisualHandle $nc --> int32)
	is native($nc-lib) is export { * }

# === Geometry ===

sub ncvisual_geom(NotcursesHandle $nc, NcvisualHandle $n, NcvisualOptions $vopts, Ncvgeom $geom --> int32)
	is native($nc-lib) is export { * }

# === Manipulation ===

sub ncvisual_rotate(NcvisualHandle $n, num64 $rads --> int32)
	is native($nc-lib) is export { * }

# ncvisual_resize is in Native.rakumod

sub ncvisual_resize_noninterpolative(NcvisualHandle $n, int32 $rows, int32 $cols --> int32)
	is native($nc-lib) is export { * }

sub ncvisual_polyfill_yx(NcvisualHandle $n, uint32 $y, uint32 $x, uint32 $rgba --> int32)
	is native($nc-lib) is export { * }

sub ncvisual_at_yx(NcvisualHandle $n, uint32 $y, uint32 $x, uint32 $pixel is rw --> int32)
	is native($nc-lib) is export { * }

sub ncvisual_set_yx(NcvisualHandle $n, uint32 $y, uint32 $x, uint32 $pixel --> int32)
	is native($nc-lib) is export { * }

# === Rendering ===

sub ncvisual_blit(NotcursesHandle $nc, NcvisualHandle $ncv, NcvisualOptions $vopts --> NcplaneHandle)
	is native($nc-lib) is export { * }

sub ncvisualplane_create(NotcursesHandle $nc, NcplaneOptions $opts, NcvisualHandle $ncv, NcvisualOptions $vopts --> NcplaneHandle)
	is native($ffi-lib) is export { * }

sub ncvisual_subtitle_plane(NcplaneHandle $parent, NcvisualHandle $ncv --> NcplaneHandle)
	is native($nc-lib) is export { * }

sub ncvisual_media_defblitter(NotcursesHandle $nc, int32 $scale --> int32)
	is native($nc-lib) is export { * }

# === Streaming ===

# streamer is ncstreamcb (callback), curry is void*
sub ncvisual_simple_streamer(NcvisualHandle $ncv, NcvisualOptions $vopts, Timespec $tspec, Pointer $curry --> int32)
	is native($nc-lib) is export { * }

# streamer is ncstreamcb (callback), curry is void*
sub ncvisual_stream(NotcursesHandle $nc, NcvisualHandle $ncv, Timespec $timescale, Pointer $streamer, NcvisualOptions $vopts, Pointer $curry --> int32)
	is native($nc-lib) is export { * }

# === Blit raw data ===

# data is raw pixel buffer
sub ncblit_rgba(Pointer $data, int32 $linesize, NcvisualOptions $vopts --> int32)
	is native($nc-lib) is export { * }

sub ncblit_bgrx(Pointer $data, int32 $linesize, NcvisualOptions $vopts --> int32)
	is native($nc-lib) is export { * }

sub ncblit_rgb_packed(Pointer $data, int32 $linesize, NcvisualOptions $vopts, int32 $alpha --> int32)
	is native($nc-lib) is export { * }

sub ncblit_rgb_loose(Pointer $data, int32 $linesize, NcvisualOptions $vopts, int32 $alpha --> int32)
	is native($nc-lib) is export { * }
