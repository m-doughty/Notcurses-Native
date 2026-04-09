#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

# Real-time clock with color cycling — press any key to quit

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";

my $std = notcurses_stdplane($nc);
my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);

my $clock-plane = ncplane_create($std, NcplaneOptions.new(
	:y(($rows / 2 - 1).Int), :x(($cols / 2 - 5).Int),
	:rows(3), :cols(10),
));

my $hue = 0;
loop {
	# Check for keypress (non-blocking)
	my $ni = Ncinput.new;
	my $key = notcurses_get_nblock($nc, $ni);
	last if $key > 0 && ($ni.id == 'q'.ord || $ni.id == NCKEY_ESC);

	# Color cycle
	my $r = ((sin($hue) + 1) * 127).Int;
	my $g = ((sin($hue + 2.094) + 1) * 127).Int;  # +2π/3
	my $b = ((sin($hue + 4.189) + 1) * 127).Int;  # +4π/3
	$hue += 0.05;

	# Draw time
	my $time = DateTime.now.hh-mm-ss;
	ncplane_erase($clock-plane);
	ncplane_set_fg_rgb8($clock-plane, $r, $g, $b);
	ncplane_on_styles($clock-plane, NCSTYLE_BOLD);
	ncplane_putstr_yx($clock-plane, 1, 1, $time);
	ncplane_off_styles($clock-plane, NCSTYLE_BOLD);

	# Dim instruction
	ncplane_set_fg_rgb8($std, 80, 80, 80);
	ncplane_putstr_yx($std, $rows - 1, ($cols - 14) div 2, 'q or Esc quits');

	notcurses_render($nc);
	sleep 0.05;
}

ncplane_destroy($clock-plane);
notcurses_stop($nc);
