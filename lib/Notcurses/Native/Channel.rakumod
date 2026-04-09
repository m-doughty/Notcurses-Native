use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Channel;

# 56 bindings — ncchannels_*, ncchannel_*, ncpixel_* functions
# All in FFI lib (static inline wrappers)

# === Single channel (32-bit) getters ===

sub ncchannel_rgb(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_r(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_g(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_b(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_rgb8(uint32 $channel, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_alpha(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_palindex(uint32 $channel --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannel_default_p(uint32 $channel --> bool)
	is native($ffi-lib) is export { * }

sub ncchannel_palindex_p(uint32 $channel --> bool)
	is native($ffi-lib) is export { * }

sub ncchannel_rgb_p(uint32 $channel --> bool)
	is native($ffi-lib) is export { * }

# === Single channel setters ===

sub ncchannel_set(uint32 $channel is rw, uint32 $rgb --> int32)
	is native($ffi-lib) is export { * }

sub ncchannel_set_rgb8(uint32 $channel is rw, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncchannel_set_rgb8_clipped(uint32 $channel is rw, int32 $r, int32 $g, int32 $b)
	is native($ffi-lib) is export { * }

sub ncchannel_set_alpha(uint32 $channel is rw, uint32 $alpha --> int32)
	is native($ffi-lib) is export { * }

sub ncchannel_set_palindex(uint32 $channel is rw, uint32 $idx --> int32)
	is native($ffi-lib) is export { * }

sub ncchannel_set_default(uint32 $channel is rw --> uint32)
	is native($ffi-lib) is export { * }

# === Dual channels (64-bit) getters ===

sub ncchannels_channels(uint64 $channels --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_fchannel(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_bchannel(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_rgb(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_rgb(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_rgb8(uint64 $channels, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_rgb8(uint64 $channels, uint32 $r is rw, uint32 $g is rw, uint32 $b is rw --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_alpha(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_alpha(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_palindex(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_palindex(uint64 $channels --> uint32)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_default_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_default_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_palindex_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_palindex_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_fg_rgb_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_bg_rgb_p(uint64 $channels --> bool)
	is native($ffi-lib) is export { * }

sub ncchannels_combine(uint32 $fchan, uint32 $bchan --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_reverse(uint64 $channels --> uint64)
	is native($ffi-lib) is export { * }

# === Dual channels setters ===

sub ncchannels_set_channels(uint64 $dst is rw, uint64 $channels --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fchannel(uint64 $channels is rw, uint32 $channel --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bchannel(uint64 $channels is rw, uint32 $channel --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_rgb(uint64 $channels is rw, uint32 $rgb --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_rgb(uint64 $channels is rw, uint32 $rgb --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_rgb8(uint64 $channels is rw, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_rgb8(uint64 $channels is rw, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_rgb8_clipped(uint64 $channels is rw, int32 $r, int32 $g, int32 $b)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_rgb8_clipped(uint64 $channels is rw, int32 $r, int32 $g, int32 $b)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_alpha(uint64 $channels is rw, uint32 $alpha --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_alpha(uint64 $channels is rw, uint32 $alpha --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_palindex(uint64 $channels is rw, uint32 $idx --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_palindex(uint64 $channels is rw, uint32 $idx --> int32)
	is native($ffi-lib) is export { * }

sub ncchannels_set_fg_default(uint64 $channels is rw --> uint64)
	is native($ffi-lib) is export { * }

sub ncchannels_set_bg_default(uint64 $channels is rw --> uint64)
	is native($ffi-lib) is export { * }

# === Pixel (32-bit ABGR) ===

sub ncpixel_r(uint32 $pixel --> uint32)
	is native($ffi-lib) is export { * }

sub ncpixel_g(uint32 $pixel --> uint32)
	is native($ffi-lib) is export { * }

sub ncpixel_b(uint32 $pixel --> uint32)
	is native($ffi-lib) is export { * }

sub ncpixel_a(uint32 $pixel --> uint32)
	is native($ffi-lib) is export { * }

sub ncpixel_set_r(uint32 $pixel is rw, uint32 $r --> int32)
	is native($ffi-lib) is export { * }

sub ncpixel_set_g(uint32 $pixel is rw, uint32 $g --> int32)
	is native($ffi-lib) is export { * }

sub ncpixel_set_b(uint32 $pixel is rw, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncpixel_set_a(uint32 $pixel is rw, uint32 $a --> int32)
	is native($ffi-lib) is export { * }

sub ncpixel_set_rgb8(uint32 $pixel is rw, uint32 $r, uint32 $g, uint32 $b --> int32)
	is native($ffi-lib) is export { * }

sub ncpixel(uint32 $r, uint32 $g, uint32 $b --> uint32)
	is native($ffi-lib) is export { * }
