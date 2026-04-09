#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Input;

# Interactive input demo: shows keypresses in real-time

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";

my $std = notcurses_stdplane($nc);
my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);

# Header
ncplane_set_fg_rgb8($std, 100, 200, 255);
ncplane_putstr_yx($std, 0, 2, 'Input Demo — press keys to see events (Escape to quit)');
ncplane_set_fg_rgb8($std, 60, 60, 60);
ncplane_putstr_yx($std, 1, 2, '─' x ($cols - 4));

# Event log area
my $log-plane = ncplane_create($std, NcplaneOptions.new(
	:y(3), :x(2),
	:rows($rows - 4), :cols($cols - 4),
	:flags(NCPLANE_OPTION_VSCROLL),
));

my $event-num = 0;
notcurses_render($nc);

loop {
	my $ni = Ncinput.new;
	my $key = notcurses_get_blocking($nc, $ni);

	last if $ni.id == NCKEY_ESC;

	$event-num++;

	# Format the event
	my $id = $ni.id;
	my $type = do given $ni.evtype {
		when NCTYPE_PRESS   { 'PRESS  ' }
		when NCTYPE_REPEAT  { 'REPEAT ' }
		when NCTYPE_RELEASE { 'RELEASE' }
		default             { 'UNKNOWN' }
	};

	# Build modifier string
	my @mods;
	@mods.push('Shift') if ncinput_shift_p($ni);
	@mods.push('Ctrl')  if ncinput_ctrl_p($ni);
	@mods.push('Alt')   if ncinput_alt_p($ni);
	@mods.push('Meta')  if ncinput_meta_p($ni);
	@mods.push('Super') if ncinput_super_p($ni);
	my $mod-str = @mods ?? @mods.join('+') ~ '+' !! '';

	# Character representation
	my $char-str = $id >= 32 && $id < 127 ?? chr($id) !! "U+{$id.fmt('%04X')}";

	my $line = sprintf('#%3d  %s  %s%s  (id=%d y=%d x=%d)',
		$event-num, $type, $mod-str, $char-str, $id, $ni.y, $ni.x);

	# Color based on type
	given $ni.evtype {
		when NCTYPE_PRESS   { ncplane_set_fg_rgb8($log-plane, 100, 255, 100) }
		when NCTYPE_RELEASE { ncplane_set_fg_rgb8($log-plane, 255, 100, 100) }
		default             { ncplane_set_fg_rgb8($log-plane, 200, 200, 100) }
	}

	ncplane_putstr_yx($log-plane, $event-num - 1, 0, $line);
	notcurses_render($nc);
}

ncplane_destroy($log-plane);
notcurses_stop($nc);
