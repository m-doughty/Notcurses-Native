use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Cell;

# 47 bindings — all nccell_*, nccells_*, nccellcmp functions
# Signatures verified against notcurses.h

# === Cell getters ===

sub nccell_channels(Nccell $c --> uint64)
	is native($ffi-lib) is export { * }

sub nccell_bchannel(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fchannel(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fg_rgb(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_bg_rgb(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fg_rgb8(Nccell $c, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_bg_rgb8(Nccell $c, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fg_alpha(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_bg_alpha(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fg_palindex(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_bg_palindex(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_fg_default_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_bg_default_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_fg_palindex_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_bg_palindex_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_double_wide_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_wide_left_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_wide_right_p(Nccell $c --> bool)
	is native($ffi-lib) is export { * }

sub nccell_cols(Nccell $c --> uint32)
	is native($ffi-lib) is export { * }

sub nccell_styles(Nccell $c --> uint16)
	is native($ffi-lib) is export { * }

# === Cell setters ===

sub nccell_init(Nccell $c)
	is native($ffi-lib) is export { * }

sub nccell_set_channels(Nccell $c, uint64 $channels --> uint64)
	is native($ffi-lib) is export { * }

sub nccell_set_bchannel(Nccell $c, uint32 $channel --> uint64)
	is native($ffi-lib) is export { * }

sub nccell_set_fchannel(Nccell $c, uint32 $channel --> uint64)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_rgb(Nccell $c, uint32 $channel --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_rgb(Nccell $c, uint32 $channel --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_rgb8(Nccell $c, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_rgb8(Nccell $c, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_rgb8_clipped(Nccell $c, int32 $r, int32 $g, int32 $b)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_rgb8_clipped(Nccell $c, int32 $r, int32 $g, int32 $b)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_alpha(Nccell $c, uint32 $alpha --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_alpha(Nccell $c, uint32 $alpha --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_default(Nccell $c)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_default(Nccell $c)
	is native($ffi-lib) is export { * }

sub nccell_set_fg_palindex(Nccell $c, uint32 $idx --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_bg_palindex(Nccell $c, uint32 $idx --> int32)
	is native($ffi-lib) is export { * }

sub nccell_set_styles(Nccell $c, uint32 $stylebits)
	is native($ffi-lib) is export { * }

sub nccell_on_styles(Nccell $c, uint32 $stylebits)
	is native($ffi-lib) is export { * }

sub nccell_off_styles(Nccell $c, uint32 $stylebits)
	is native($ffi-lib) is export { * }

# === Cell load/release/dup ===

sub nccell_load(NcplaneHandle $n, Nccell $c, Str $gcluster --> int32)
	is native($core-lib) is export { * }

sub nccell_release(NcplaneHandle $n, Nccell $c)
	is native($core-lib) is export { * }

sub nccell_duplicate(NcplaneHandle $n, Nccell $targ, Nccell $c --> int32)
	is native($core-lib) is export { * }

sub nccell_prime(NcplaneHandle $n, Nccell $c, Str $gcluster, uint16 $stylemask, uint64 $channels --> int32)
	is native($ffi-lib) is export { * }

sub nccell_load_char(NcplaneHandle $n, Nccell $c, uint8 $ch --> int32)
	is native($ffi-lib) is export { * }

sub nccell_load_egc32(NcplaneHandle $n, Nccell $c, uint32 $egc --> int32)
	is native($ffi-lib) is export { * }

sub nccell_load_ucs32(NcplaneHandle $n, Nccell $c, uint32 $u --> int32)
	is native($ffi-lib) is export { * }

# === Cell extract/strdup ===

sub nccell_extract(NcplaneHandle $n, Nccell $c, uint16 $stylemask is rw, uint64 $channels is rw --> Str)
	is native($ffi-lib) is export { * }

sub nccell_strdup(NcplaneHandle $n, Nccell $c --> Str)
	is native($ffi-lib) is export { * }

sub nccell_extended_gcluster(NcplaneHandle $n, Nccell $c --> Str)
	is native($core-lib) is export { * }

# === Cell comparison ===

sub nccellcmp(NcplaneHandle $n1, Nccell $c1, NcplaneHandle $n2, Nccell $c2 --> bool)
	is native($ffi-lib) is export { * }

# === Box cell helpers ===

sub nccells_ascii_box(NcplaneHandle $n, uint16 $attr, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl --> int32)
	is native($ffi-lib) is export { * }

sub nccells_double_box(NcplaneHandle $n, uint16 $attr, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl --> int32)
	is native($ffi-lib) is export { * }

sub nccells_rounded_box(NcplaneHandle $n, uint16 $attr, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl --> int32)
	is native($ffi-lib) is export { * }

sub nccells_light_box(NcplaneHandle $n, uint16 $attr, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl --> int32)
	is native($ffi-lib) is export { * }

sub nccells_heavy_box(NcplaneHandle $n, uint16 $attr, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl --> int32)
	is native($ffi-lib) is export { * }

sub nccells_load_box(NcplaneHandle $n, uint16 $styles, uint64 $channels,
	Nccell $ul, Nccell $ur, Nccell $ll, Nccell $lr, Nccell $hl, Nccell $vl,
	Str $gclusters --> int32)
	is native($ffi-lib) is export { * }
