use NativeCall;

unit module Notcurses::Native::Types;

# === CStruct Str field helper ===
# NativeCall CStruct cannot set Str fields via the constructor.
# This helper writes a C string pointer at the given field offset.
my @cstruct-str-refs;  # prevent GC of allocated string buffers

sub set-cstruct-str($struct, Int $offset, Str $value) is export {
	return unless $value.defined;
	my $buf = CArray[uint8].new($value.encode("utf8").list, 0);
	@cstruct-str-refs.push($buf);
	nativecast(CArray[Pointer], $struct)[$offset] = nativecast(Pointer, $buf);
}

# === Opaque pointer types ===

class NotcursesHandle is repr('CPointer') is export { }
class NcplaneHandle  is repr('CPointer') is export { }
class NcvisualHandle is repr('CPointer') is export { }
class NcdirectHandle is repr('CPointer') is export { }
class NcreelHandle   is repr('CPointer') is export { }
class NcmenuHandle   is repr('CPointer') is export { }
class NctreeHandle   is repr('CPointer') is export { }
class NcreaderHandle is repr('CPointer') is export { }
class NcselectorHandle      is repr('CPointer') is export { }
class NcmultiselectorHandle is repr('CPointer') is export { }
class NctabbedHandle is repr('CPointer') is export { }
class NcuplotHandle  is repr('CPointer') is export { }
class NcdplotHandle  is repr('CPointer') is export { }
class NcprogbarHandle is repr('CPointer') is export { }
class NcsubprocHandle is repr('CPointer') is export { }
class NcfdplaneHandle is repr('CPointer') is export { }
class NcfadectxHandle is repr('CPointer') is export { }
class NcpaletteHandle is repr('CPointer') is export { }
class NctabHandle     is repr('CPointer') is export { }

# === Log levels ===

enum NcLogLevel is export (
	NCLOGLEVEL_SILENT  => -1,
	NCLOGLEVEL_PANIC   => 0,
	NCLOGLEVEL_FATAL   => 1,
	NCLOGLEVEL_ERROR   => 2,
	NCLOGLEVEL_WARNING => 3,
	NCLOGLEVEL_INFO    => 4,
	NCLOGLEVEL_VERBOSE => 5,
	NCLOGLEVEL_DEBUG   => 6,
	NCLOGLEVEL_TRACE   => 7,
);

# === Alignment ===

enum NcAlign is export (
	NCALIGN_UNALIGNED => 0,
	NCALIGN_LEFT      => 1,
	NCALIGN_CENTER    => 2,
	NCALIGN_RIGHT     => 3,
);

# === Blitter ===

enum NcBlitter is export (
	NCBLIT_DEFAULT  => 0,
	NCBLIT_1x1      => 1,
	NCBLIT_2x1      => 2,
	NCBLIT_2x2      => 3,
	NCBLIT_3x2      => 4,
	NCBLIT_4x2      => 5,
	NCBLIT_BRAILLE  => 6,
	NCBLIT_PIXEL    => 7,
	NCBLIT_4x1      => 8,
	NCBLIT_8x1      => 9,
);

# === Scale ===

enum NcScale is export (
	NCSCALE_NONE        => 0,
	NCSCALE_SCALE       => 1,
	NCSCALE_STRETCH     => 2,
	NCSCALE_NONE_HIRES  => 3,
	NCSCALE_SCALE_HIRES => 4,
);

# === Input event type ===

enum NcInputType is export (
	NCTYPE_UNKNOWN => 0,
	NCTYPE_PRESS   => 1,
	NCTYPE_REPEAT  => 2,
	NCTYPE_RELEASE => 3,
);

# === Style masks ===

constant NCSTYLE_MASK      is export = 0xFFFF;
constant NCSTYLE_ITALIC    is export = 0x0010;
constant NCSTYLE_UNDERLINE is export = 0x0008;
constant NCSTYLE_UNDERCURL is export = 0x0004;
constant NCSTYLE_BOLD      is export = 0x0002;
constant NCSTYLE_STRUCK    is export = 0x0020;
constant NCSTYLE_NONE      is export = 0x0000;

# === Option flags ===

constant NCOPTION_INHIBIT_SETLOCALE   is export = 0x0001;
constant NCOPTION_NO_CLEAR_BITMAPS    is export = 0x0002;
constant NCOPTION_NO_WINCH_SIGHANDLER is export = 0x0004;
constant NCOPTION_NO_QUIT_SIGHANDLERS is export = 0x0008;
constant NCOPTION_PRESERVE_CURSOR     is export = 0x0010;
constant NCOPTION_SUPPRESS_BANNERS    is export = 0x0020;
constant NCOPTION_NO_ALTERNATE_SCREEN is export = 0x0040;
constant NCOPTION_NO_FONT_CHANGES     is export = 0x0080;
constant NCOPTION_DRAIN_INPUT         is export = 0x0100;
constant NCOPTION_SCROLLING           is export = 0x0200;
constant NCOPTION_CLI_MODE            is export = 0x0600;  # SCROLLING | NO_ALTERNATE_SCREEN | PRESERVE_CURSOR

# === Plane option flags ===

constant NCPLANE_OPTION_HORALIGNED    is export = 0x0001;
constant NCPLANE_OPTION_VERALIGNED    is export = 0x0002;
constant NCPLANE_OPTION_MARGINALIZED  is export = 0x0004;
constant NCPLANE_OPTION_FIXED         is export = 0x0008;
constant NCPLANE_OPTION_AUTOGROW      is export = 0x0010;
constant NCPLANE_OPTION_VSCROLL       is export = 0x0020;

# === CStruct: notcurses_options ===

class NotcursesOptions is repr('CStruct') is export {
	has Str $.termtype;          # offset 0
	has int32 $.loglevel = 0;    # ncloglevel_e
	has uint32 $.margin_t = 0;
	has uint32 $.margin_r = 0;
	has uint32 $.margin_b = 0;
	has uint32 $.margin_l = 0;
	has uint64 $.flags = 0;

	multi method new(Str :$termtype, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $termtype);
		$self
	}
}

# === CStruct: ncplane_options ===

class NcplaneOptions is repr('CStruct') is export {
	has int32 $.y = 0;
	has int32 $.x = 0;
	has uint32 $.rows = 1;
	has uint32 $.cols = 1;
	has Pointer $.userptr;
	has Str $.name;              # offset 3
	has Pointer $.resizecb;      # function pointer
	has uint64 $.flags = 0;
	has uint32 $.margin_b = 0;
	has uint32 $.margin_r = 0;

	multi method new(Str :$name, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 3, $name);
		$self
	}
}

# === CStruct: nccell (16 bytes) ===

class Nccell is repr('CStruct') is export {
	has uint32 $.gcluster = 0;
	has uint8 $.gcluster_backstop = 0;
	has uint8 $.width = 1;
	has uint16 $.stylemask = 0;
	has uint64 $.channels = 0;
}

# === CStruct: ncinput ===

class Ncinput is repr('CStruct') is export {
	has uint32 $.id = 0;
	has int32 $.y = -1;
	has int32 $.x = -1;
	# utf8[5] — 5 bytes inline, represented as individual bytes
	has uint8 $.utf8_0 = 0;
	has uint8 $.utf8_1 = 0;
	has uint8 $.utf8_2 = 0;
	has uint8 $.utf8_3 = 0;
	has uint8 $.utf8_4 = 0;
	# deprecated bools
	has uint8 $.alt = 0;    # bool
	has uint8 $.shift = 0;  # bool
	has uint8 $.ctrl = 0;   # bool
	has int32 $.evtype = 0; # ncintype_e
	has uint32 $.modifiers = 0;
	has int32 $.ypx = -1;
	has int32 $.xpx = -1;
	# eff_text[4] — 4 x uint32
	has uint32 $.eff_text_0 = 0;
	has uint32 $.eff_text_1 = 0;
	has uint32 $.eff_text_2 = 0;
	has uint32 $.eff_text_3 = 0;
}

# === Key modifier bitmasks ===

constant NCKEY_MOD_SHIFT  is export = 1;
constant NCKEY_MOD_ALT    is export = 2;
constant NCKEY_MOD_CTRL   is export = 4;
constant NCKEY_MOD_SUPER  is export = 8;
constant NCKEY_MOD_HYPER  is export = 16;
constant NCKEY_MOD_META   is export = 32;
constant NCKEY_MOD_CAPSLOCK is export = 64;
constant NCKEY_MOD_NUMLOCK  is export = 128;

# === Key codes (NCKEY_*) ===
# Base: preterunicode(w) = w + 1115000

constant NCKEY_INVALID   is export = 1115000;
constant NCKEY_RESIZE    is export = 1115001;
constant NCKEY_UP        is export = 1115002;
constant NCKEY_RIGHT     is export = 1115003;
constant NCKEY_DOWN      is export = 1115004;
constant NCKEY_LEFT      is export = 1115005;
constant NCKEY_INS       is export = 1115006;
constant NCKEY_DEL       is export = 1115007;
constant NCKEY_BACKSPACE is export = 1115008;
constant NCKEY_PGDOWN    is export = 1115009;
constant NCKEY_PGUP      is export = 1115010;
constant NCKEY_HOME      is export = 1115011;
constant NCKEY_END       is export = 1115012;
constant NCKEY_F00       is export = 1115020;
constant NCKEY_F01       is export = 1115021;
constant NCKEY_F02       is export = 1115022;
constant NCKEY_F03       is export = 1115023;
constant NCKEY_F04       is export = 1115024;
constant NCKEY_F05       is export = 1115025;
constant NCKEY_F06       is export = 1115026;
constant NCKEY_F07       is export = 1115027;
constant NCKEY_F08       is export = 1115028;
constant NCKEY_F09       is export = 1115029;
constant NCKEY_F10       is export = 1115030;
constant NCKEY_F11       is export = 1115031;
constant NCKEY_F12       is export = 1115032;
constant NCKEY_F13       is export = 1115033;
constant NCKEY_F14       is export = 1115034;
constant NCKEY_F15       is export = 1115035;
constant NCKEY_F16       is export = 1115036;
constant NCKEY_F17       is export = 1115037;
constant NCKEY_F18       is export = 1115038;
constant NCKEY_F19       is export = 1115039;
constant NCKEY_F20       is export = 1115040;
constant NCKEY_F21       is export = 1115041;
constant NCKEY_F22       is export = 1115042;
constant NCKEY_F23       is export = 1115043;
constant NCKEY_F24       is export = 1115044;
constant NCKEY_F25       is export = 1115045;
constant NCKEY_F26       is export = 1115046;
constant NCKEY_F27       is export = 1115047;
constant NCKEY_F28       is export = 1115048;
constant NCKEY_F29       is export = 1115049;
constant NCKEY_F30       is export = 1115050;
constant NCKEY_F31       is export = 1115051;
constant NCKEY_F32       is export = 1115052;
constant NCKEY_F33       is export = 1115053;
constant NCKEY_F34       is export = 1115054;
constant NCKEY_F35       is export = 1115055;
constant NCKEY_F36       is export = 1115056;
constant NCKEY_F37       is export = 1115057;
constant NCKEY_F38       is export = 1115058;
constant NCKEY_F39       is export = 1115059;
constant NCKEY_F40       is export = 1115060;
constant NCKEY_F41       is export = 1115061;
constant NCKEY_F42       is export = 1115062;
constant NCKEY_F43       is export = 1115063;
constant NCKEY_F44       is export = 1115064;
constant NCKEY_F45       is export = 1115065;
constant NCKEY_F46       is export = 1115066;
constant NCKEY_F47       is export = 1115067;
constant NCKEY_F48       is export = 1115068;
constant NCKEY_F49       is export = 1115069;
constant NCKEY_F50       is export = 1115070;
constant NCKEY_F51       is export = 1115071;
constant NCKEY_F52       is export = 1115072;
constant NCKEY_F53       is export = 1115073;
constant NCKEY_F54       is export = 1115074;
constant NCKEY_F55       is export = 1115075;
constant NCKEY_F56       is export = 1115076;
constant NCKEY_F57       is export = 1115077;
constant NCKEY_F58       is export = 1115078;
constant NCKEY_F59       is export = 1115079;
constant NCKEY_F60       is export = 1115080;
constant NCKEY_ENTER     is export = 1115121;
constant NCKEY_CLS       is export = 1115122;
constant NCKEY_DLEFT     is export = 1115123;
constant NCKEY_DRIGHT    is export = 1115124;
constant NCKEY_ULEFT     is export = 1115125;
constant NCKEY_URIGHT    is export = 1115126;
constant NCKEY_CENTER    is export = 1115127;
constant NCKEY_BEGIN     is export = 1115128;
constant NCKEY_CANCEL    is export = 1115129;
constant NCKEY_CLOSE     is export = 1115130;
constant NCKEY_COMMAND   is export = 1115131;
constant NCKEY_COPY      is export = 1115132;
constant NCKEY_EXIT      is export = 1115133;
constant NCKEY_PRINT     is export = 1115134;
constant NCKEY_REFRESH   is export = 1115135;
constant NCKEY_SEPARATOR is export = 1115136;

# Lock keys
constant NCKEY_CAPS_LOCK    is export = 1115150;
constant NCKEY_SCROLL_LOCK  is export = 1115151;
constant NCKEY_NUM_LOCK     is export = 1115152;
constant NCKEY_PRINT_SCREEN is export = 1115153;
constant NCKEY_PAUSE        is export = 1115154;
constant NCKEY_MENU         is export = 1115155;

# Media keys
constant NCKEY_MEDIA_PLAY   is export = 1115158;
constant NCKEY_MEDIA_PAUSE  is export = 1115159;
constant NCKEY_MEDIA_PPAUSE is export = 1115160;
constant NCKEY_MEDIA_REV    is export = 1115161;
constant NCKEY_MEDIA_STOP   is export = 1115162;
constant NCKEY_MEDIA_FF     is export = 1115163;
constant NCKEY_MEDIA_REWIND is export = 1115164;
constant NCKEY_MEDIA_NEXT   is export = 1115165;
constant NCKEY_MEDIA_PREV   is export = 1115166;
constant NCKEY_MEDIA_RECORD is export = 1115167;
constant NCKEY_MEDIA_LVOL   is export = 1115168;
constant NCKEY_MEDIA_RVOL   is export = 1115169;
constant NCKEY_MEDIA_MUTE   is export = 1115170;

# Individual modifier keys (when reported as keypresses)
constant NCKEY_LSHIFT    is export = 1115171;
constant NCKEY_LCTRL     is export = 1115172;
constant NCKEY_LALT      is export = 1115173;
constant NCKEY_LSUPER    is export = 1115174;
constant NCKEY_LHYPER    is export = 1115175;
constant NCKEY_LMETA     is export = 1115176;
constant NCKEY_RSHIFT    is export = 1115177;
constant NCKEY_RCTRL     is export = 1115178;
constant NCKEY_RALT      is export = 1115179;
constant NCKEY_RSUPER    is export = 1115180;
constant NCKEY_RHYPER    is export = 1115181;
constant NCKEY_RMETA     is export = 1115182;
constant NCKEY_L3SHIFT   is export = 1115183;
constant NCKEY_L5SHIFT   is export = 1115184;

# Mouse events
constant NCKEY_MOTION    is export = 1115200;
constant NCKEY_BUTTON1   is export = 1115201;
constant NCKEY_BUTTON2   is export = 1115202;
constant NCKEY_BUTTON3   is export = 1115203;
constant NCKEY_BUTTON4   is export = 1115204;  # scroll up
constant NCKEY_BUTTON5   is export = 1115205;  # scroll down
constant NCKEY_BUTTON6   is export = 1115206;
constant NCKEY_BUTTON7   is export = 1115207;
constant NCKEY_BUTTON8   is export = 1115208;
constant NCKEY_BUTTON9   is export = 1115209;
constant NCKEY_BUTTON10  is export = 1115210;
constant NCKEY_BUTTON11  is export = 1115211;

# Special
constant NCKEY_SIGNAL    is export = 1115400;
constant NCKEY_EOF       is export = 1115500;

# Aliases
constant NCKEY_SCROLL_UP   is export = NCKEY_BUTTON4;
constant NCKEY_SCROLL_DOWN is export = NCKEY_BUTTON5;
constant NCKEY_RETURN      is export = NCKEY_ENTER;
constant NCKEY_TAB         is export = 0x09;
constant NCKEY_ESC         is export = 0x1b;
constant NCKEY_SPACE       is export = 0x20;

# === Mouse event subscription flags ===

constant NCMICE_NO_EVENTS    is export = 0;
constant NCMICE_MOVE_EVENT   is export = 0x1;
constant NCMICE_BUTTON_EVENT is export = 0x2;
constant NCMICE_DRAG_EVENT   is export = 0x4;
constant NCMICE_ALL_EVENTS   is export = 0x7;

# === Alignment aliases (vertical = horizontal mapping) ===

constant NCALIGN_TOP    is export = 1;  # same as NCALIGN_LEFT
constant NCALIGN_BOTTOM is export = 3;  # same as NCALIGN_RIGHT

# === Channel bitmasks (for manual channel manipulation) ===

constant NC_BG_RGB_MASK      is export = 0x0000000000FFFFFF;
constant NC_BG_PALETTE       is export = 0x0000000008000000;
constant NC_BG_ALPHA_MASK    is export = 0x30000000;
constant NC_BGDEFAULT_MASK   is export = 0x0000000040000000;
constant NC_NOBACKGROUND_MASK is export = 0x8700000000000000;

# === Miscellaneous constants ===

constant NCPALETTESIZE                  is export = 256;
constant NCINPUT_MAX_EFF_TEXT_CODEPOINTS is export = 4;

# === Pixel implementation enum ===

enum NcPixelImpl is export (
	NCPIXEL_NONE           => 0,
	NCPIXEL_SIXEL          => 1,
	NCPIXEL_LINUXFB        => 2,
	NCPIXEL_ITERM2         => 3,
	NCPIXEL_KITTY_STATIC   => 4,
	NCPIXEL_KITTY_ANIMATED => 5,
	NCPIXEL_KITTY_SELFREF  => 6,
);

# === Box drawing control flags ===

constant NCBOXMASK_TOP    is export = 0x0001;
constant NCBOXMASK_RIGHT  is export = 0x0002;
constant NCBOXMASK_BOTTOM is export = 0x0004;
constant NCBOXMASK_LEFT   is export = 0x0008;
constant NCBOXGRAD_TOP    is export = 0x0010;
constant NCBOXGRAD_RIGHT  is export = 0x0020;
constant NCBOXGRAD_BOTTOM is export = 0x0040;
constant NCBOXGRAD_LEFT   is export = 0x0080;
constant NCBOXCORNER_MASK is export = 0x0300;
constant NCBOXCORNER_SHIFT is export = 8;

# === Alpha constants ===

constant NCALPHA_HIGHCONTRAST is export = 0x30000000;
constant NCALPHA_TRANSPARENT  is export = 0x20000000;
constant NCALPHA_BLEND        is export = 0x10000000;
constant NCALPHA_OPAQUE       is export = 0x00000000;

# === Visual option flags ===

constant NCVISUAL_OPTION_NODEGRADE     is export = 0x0001;
constant NCVISUAL_OPTION_BLEND         is export = 0x0002;
constant NCVISUAL_OPTION_HORALIGNED    is export = 0x0004;
constant NCVISUAL_OPTION_VERALIGNED    is export = 0x0008;
constant NCVISUAL_OPTION_ADDALPHA      is export = 0x0010;
constant NCVISUAL_OPTION_CHILDPLANE    is export = 0x0020;
constant NCVISUAL_OPTION_NOINTERPOLATE is export = 0x0040;

# === Reel option flags ===

constant NCREEL_OPTION_INFINITESCROLL is export = 0x0001;
constant NCREEL_OPTION_CIRCULAR       is export = 0x0002;

# === Plot option flags ===

constant NCPLOT_OPTION_LABELTICKSD  is export = 0x0001;
constant NCPLOT_OPTION_EXPONENTIALD is export = 0x0002;
constant NCPLOT_OPTION_VERTICALI    is export = 0x0004;
constant NCPLOT_OPTION_NODEGRADE    is export = 0x0008;
constant NCPLOT_OPTION_DETECTMAXONLY is export = 0x0010;
constant NCPLOT_OPTION_PRINTSAMPLE  is export = 0x0020;

# === Reader option flags ===

constant NCREADER_OPTION_HORSCROLL  is export = 0x0001;
constant NCREADER_OPTION_VERSCROLL  is export = 0x0002;
constant NCREADER_OPTION_NOCMDKEYS  is export = 0x0004;
constant NCREADER_OPTION_CURSOR     is export = 0x0008;

# === Progbar option flags ===

constant NCPROGBAR_OPTION_RETROGRADE is export = 0x0001;

# === Tabbed option flags ===

constant NCTABBED_OPTION_BOTTOM is export = 0x0001;

# === Menu option flags ===

constant NCMENU_OPTION_BOTTOM is export = 0x0001;
constant NCMENU_OPTION_HIDING is export = 0x0002;

# === CStruct: timespec (POSIX) ===

class Timespec is repr('CStruct') is export {
	has long $.tv_sec = 0;
	has long $.tv_nsec = 0;
}

# === CStruct: nccapabilities ===

class Nccapabilities is repr('CStruct') is export {
	has uint32 $.colors = 0;
	has bool $.utf8 = False;
	has bool $.rgb = False;
	has bool $.can_change_colors = False;
	has bool $.halfblocks = False;
	has bool $.quadrants = False;
	has bool $.sextants = False;
	has bool $.octants = False;
	has bool $.braille = False;
}

# === CStruct: ncstats ===

class Ncstats is repr('CStruct') is export {
	has uint64 $.renders = 0;
	has uint64 $.writeouts = 0;
	has uint64 $.failed_renders = 0;
	has uint64 $.failed_writeouts = 0;
	has uint64 $.raster_bytes = 0;
	has int64 $.raster_max_bytes = 0;
	has int64 $.raster_min_bytes = 0;
	has uint64 $.render_ns = 0;
	has int64 $.render_max_ns = 0;
	has int64 $.render_min_ns = 0;
	has uint64 $.raster_ns = 0;
	has int64 $.raster_max_ns = 0;
	has int64 $.raster_min_ns = 0;
	has uint64 $.writeout_ns = 0;
	has int64 $.writeout_max_ns = 0;
	has int64 $.writeout_min_ns = 0;
	has uint64 $.cellelisions = 0;
	has uint64 $.cellemissions = 0;
	has uint64 $.fgelisions = 0;
	has uint64 $.fgemissions = 0;
	has uint64 $.bgelisions = 0;
	has uint64 $.bgemissions = 0;
	has uint64 $.defaultelisions = 0;
	has uint64 $.defaultemissions = 0;
	has uint64 $.refreshes = 0;
	has uint64 $.sprixelemissions = 0;
	has uint64 $.sprixelelisions = 0;
	has uint64 $.sprixelbytes = 0;
	has uint64 $.appsync_updates = 0;
	has uint64 $.input_errors = 0;
	has uint64 $.input_events = 0;
	has uint64 $.hpa_gratuitous = 0;
	has uint64 $.cell_geo_changes = 0;
	has uint64 $.pixel_geo_changes = 0;
	has uint64 $.fbbytes = 0;
	has uint32 $.planes = 0;
}

# === CStruct: ncvgeom (visual geometry) ===

class Ncvgeom is repr('CStruct') is export {
	has uint32 $.pixy = 0;
	has uint32 $.pixx = 0;
	has uint32 $.cdimy = 0;
	has uint32 $.cdimx = 0;
	has uint32 $.rpixy = 0;
	has uint32 $.rpixx = 0;
	has uint32 $.rcelly = 0;
	has uint32 $.rcellx = 0;
	has uint32 $.scaley = 0;
	has uint32 $.scalex = 0;
	has uint32 $.begy = 0;
	has uint32 $.begx = 0;
	has uint32 $.leny = 0;
	has uint32 $.lenx = 0;
	has uint32 $.maxpixely = 0;
	has uint32 $.maxpixelx = 0;
	has int32 $.blitter = 0;  # ncblitter_e
}

# === CStruct: ncvisual_options ===

class NcvisualOptions is repr('CStruct') is export {
	has Pointer $.n;             # ncplane* (existing plane or parent), offset 0
	has int32 $.scaling = 0;     # ncscale_e
	has int32 $.y = 0;
	has int32 $.x = 0;
	has uint32 $.begy = 0;       # origin of rendered region in pixels
	has uint32 $.begx = 0;
	has uint32 $.leny = 0;       # size of rendered region in pixels
	has uint32 $.lenx = 0;
	has int32 $.blitter = 0;     # ncblitter_e
	has uint64 $.flags = 0;
	has uint32 $.transcolor = 0;
	has uint32 $.pxoffy = 0;     # pixel offsets within cell
	has uint32 $.pxoffx = 0;

	# Set the target plane — blits onto this plane instead of creating a new one
	method set-plane($plane) {
		nativecast(CArray[Pointer], self)[0] = nativecast(Pointer, $plane);
		self
	}
}

# === CStruct: ncreel_options ===

class NcreelOptions is repr('CStruct') is export {
	has uint32 $.bordermask = 0;
	has uint64 $.borderchan = 0;
	has uint32 $.tabletmask = 0;
	has uint64 $.tabletchan = 0;
	has uint64 $.focusedchan = 0;
	has uint64 $.flags = 0;
}

# === CStruct: ncselector_item ===

class NcselectorItem is repr('CStruct') is export {
	has Str $.option;            # offset 0
	has Str $.desc;              # offset 1

	multi method new(Str :$option, Str :$desc, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $option);
		set-cstruct-str($self, 1, $desc);
		$self
	}
}

# === CStruct: ncselector_options ===

class NcselectorOptions is repr('CStruct') is export {
	has Str $.title;              # offset 0
	has Str $.secondary;          # offset 1
	has Str $.footer;             # offset 2
	has Pointer $.items;          # const ncselector_item*
	has uint32 $.defidx = 0;
	has uint32 $.maxdisplay = 0;
	has uint64 $.opchannels = 0;
	has uint64 $.descchannels = 0;
	has uint64 $.titlechannels = 0;
	has uint64 $.footchannels = 0;
	has uint64 $.boxchannels = 0;
	has uint64 $.flags = 0;

	multi method new(Str :$title, Str :$secondary, Str :$footer, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $title);
		set-cstruct-str($self, 1, $secondary);
		set-cstruct-str($self, 2, $footer);
		$self
	}
}

# === CStruct: ncmselector_item ===

class NcmselectorItem is repr('CStruct') is export {
	has Str $.option;            # offset 0
	has Str $.desc;              # offset 1
	has bool $.selected = False;

	multi method new(Str :$option, Str :$desc, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $option);
		set-cstruct-str($self, 1, $desc);
		$self
	}
}

# === CStruct: ncmultiselector_options ===

class NcmultiselectorOptions is repr('CStruct') is export {
	has Str $.title;              # offset 0
	has Str $.secondary;          # offset 1
	has Str $.footer;             # offset 2
	has Pointer $.items;          # const ncmselector_item*
	has uint32 $.maxdisplay = 0;
	has uint64 $.opchannels = 0;
	has uint64 $.descchannels = 0;
	has uint64 $.titlechannels = 0;
	has uint64 $.footchannels = 0;
	has uint64 $.boxchannels = 0;
	has uint64 $.flags = 0;

	multi method new(Str :$title, Str :$secondary, Str :$footer, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $title);
		set-cstruct-str($self, 1, $secondary);
		set-cstruct-str($self, 2, $footer);
		$self
	}
}

# === CStruct: nctree_item ===

class NctreeItem is repr('CStruct') is export {
	has Pointer $.curry;          # void*
	has Pointer $.subs;           # nctree_item*
	has uint32 $.subcount = 0;
}

# === CStruct: nctree_options ===

class NctreeOptions is repr('CStruct') is export {
	has Pointer $.items;          # const nctree_item*
	has uint32 $.count = 0;
	has Pointer $.nctreecb;       # callback function pointer
	has int32 $.indentcols = 0;
	has uint64 $.flags = 0;
}

# === CStruct: ncmenu_item ===
# Contains embedded Ncinput (not a pointer) — this is a large struct.
# Ncinput is 60 bytes, so ncmenu_item is: Str(8) + Ncinput(60) = 68 bytes

class NcmenuItem is repr('CStruct') is export {
	has Str $.desc;              # offset 0
	# Embedded ncinput shortcut — inline all fields
	has uint32 $.shortcut_id = 0;
	has int32 $.shortcut_y = -1;
	has int32 $.shortcut_x = -1;
	has uint8 $.shortcut_utf8_0 = 0;
	has uint8 $.shortcut_utf8_1 = 0;
	has uint8 $.shortcut_utf8_2 = 0;
	has uint8 $.shortcut_utf8_3 = 0;
	has uint8 $.shortcut_utf8_4 = 0;
	has uint8 $.shortcut_alt = 0;
	has uint8 $.shortcut_shift = 0;
	has uint8 $.shortcut_ctrl = 0;
	has int32 $.shortcut_evtype = 0;
	has uint32 $.shortcut_modifiers = 0;
	has int32 $.shortcut_ypx = -1;
	has int32 $.shortcut_xpx = -1;
	has uint32 $.shortcut_eff_text_0 = 0;
	has uint32 $.shortcut_eff_text_1 = 0;
	has uint32 $.shortcut_eff_text_2 = 0;
	has uint32 $.shortcut_eff_text_3 = 0;

	multi method new(Str :$desc, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $desc);
		$self
	}
}

# === CStruct: ncmenu_section ===

class NcmenuSection is repr('CStruct') is export {
	has Str $.name;              # offset 0
	has int32 $.itemcount = 0;
	has Pointer $.items;          # ncmenu_item*
	# Embedded ncinput shortcut — inline all fields
	has uint32 $.shortcut_id = 0;
	has int32 $.shortcut_y = -1;
	has int32 $.shortcut_x = -1;
	has uint8 $.shortcut_utf8_0 = 0;
	has uint8 $.shortcut_utf8_1 = 0;
	has uint8 $.shortcut_utf8_2 = 0;
	has uint8 $.shortcut_utf8_3 = 0;
	has uint8 $.shortcut_utf8_4 = 0;
	has uint8 $.shortcut_alt = 0;
	has uint8 $.shortcut_shift = 0;
	has uint8 $.shortcut_ctrl = 0;
	has int32 $.shortcut_evtype = 0;
	has uint32 $.shortcut_modifiers = 0;
	has int32 $.shortcut_ypx = -1;
	has int32 $.shortcut_xpx = -1;
	has uint32 $.shortcut_eff_text_0 = 0;
	has uint32 $.shortcut_eff_text_1 = 0;
	has uint32 $.shortcut_eff_text_2 = 0;
	has uint32 $.shortcut_eff_text_3 = 0;

	multi method new(Str :$name, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 0, $name);
		$self
	}
}

# === CStruct: ncmenu_options ===

class NcmenuOptions is repr('CStruct') is export {
	has Pointer $.sections;       # ncmenu_section*
	has int32 $.sectioncount = 0;
	has uint64 $.headerchannels = 0;
	has uint64 $.sectionchannels = 0;
	has uint64 $.flags = 0;
}

# === CStruct: ncprogbar_options ===

class NcprogbarOptions is repr('CStruct') is export {
	has uint32 $.ulchannel = 0;
	has uint32 $.urchannel = 0;
	has uint32 $.blchannel = 0;
	has uint32 $.brchannel = 0;
	has uint64 $.flags = 0;
}

# === CStruct: nctabbed_options ===

class NctabbedOptions is repr('CStruct') is export {
	has uint64 $.selchan = 0;
	has uint64 $.hdrchan = 0;
	has uint64 $.sepchan = 0;
	has Str $.separator;         # offset 3
	has uint64 $.flags = 0;

	multi method new(Str :$separator, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 3, $separator);
		$self
	}
}

# === CStruct: ncplot_options ===

class NcplotOptions is repr('CStruct') is export {
	has uint64 $.maxchannels = 0;
	has uint64 $.minchannels = 0;
	has uint16 $.legendstyle = 0;
	has int32 $.gridtype = 0;    # ncblitter_e
	has int32 $.rangex = 0;
	has Str $.title;             # offset 4 (after 16 + 2+pad+4+4 = 32 bytes)
	has uint64 $.flags = 0;

	multi method new(Str :$title, *%rest) {
		my $self = callwith(|%rest);
		set-cstruct-str($self, 4, $title);
		$self
	}
}

# === CStruct: ncfdplane_options ===

class NcfdplaneOptions is repr('CStruct') is export {
	has Pointer $.curry;          # void*
	has bool $.follow = False;
	has uint64 $.flags = 0;
}

# === CStruct: ncsubproc_options ===

class NcsubprocOptions is repr('CStruct') is export {
	has Pointer $.curry;          # void*
	has uint64 $.restart_period = 0;
	has uint64 $.flags = 0;
}

# === CStruct: ncreader_options ===

class NcreaderOptions is repr('CStruct') is export {
	has uint64 $.tchannels = 0;
	has uint32 $.tattrword = 0;
	has uint64 $.flags = 0;
}
