use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native;

unit module Notcurses::Native::Input;

# 15 bindings — ncinput_* and nckey_* functions
# All in FFI lib

sub ncinput_shift_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_ctrl_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_alt_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_meta_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_super_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_hyper_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_capslock_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_numlock_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_nomod_p(Ncinput $n --> bool)
	is native($ffi-lib) is export { * }

sub ncinput_equal_p(Ncinput $n1, Ncinput $n2 --> bool)
	is native($ffi-lib) is export { * }

sub nckey_mouse_p(uint32 $r --> bool)
	is native($ffi-lib) is export { * }

sub nckey_synthesized_p(uint32 $w --> bool)
	is native($ffi-lib) is export { * }

sub nckey_pua_p(uint32 $w --> bool)
	is native($ffi-lib) is export { * }

sub nckey_supppuaa_p(uint32 $w --> bool)
	is native($ffi-lib) is export { * }

sub nckey_supppuab_p(uint32 $w --> bool)
	is native($ffi-lib) is export { * }
