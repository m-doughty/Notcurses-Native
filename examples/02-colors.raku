#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Context;

# Display a color palette showing terminal capabilities

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";

my $std = notcurses_stdplane($nc);
my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);

# Title
ncplane_set_fg_rgb8($std, 255, 255, 255);
ncplane_putstr_yx($std, 0, 2, 'Notcurses Color Palette');
ncplane_putstr_yx($std, 1, 2, '══════════════════════');

# Capabilities
my $tc = notcurses_cantruecolor($nc);
my $palsize = notcurses_palette_size($nc);
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 2, 2, "Truecolor: {$tc ?? 'yes' !! 'no'}  Palette: $palsize colors");

# RGB gradient bar
ncplane_putstr_yx($std, 4, 2, 'RGB Gradient:');
my $bar-width = min($cols - 4, 64);
for ^$bar-width -> $i {
	my $r = (255 * $i / $bar-width).Int;
	my $g = (255 * (1 - ($i / $bar-width - 0.5).abs * 2)).Int;
	my $b = (255 * ($bar-width - $i) / $bar-width).Int;
	ncplane_set_bg_rgb8($std, $r, $g, $b);
	ncplane_putstr_yx($std, 5, 2 + $i, ' ');
}
ncplane_set_bg_default($std);

# Red gradient
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 7, 2, 'Red:');
for ^$bar-width -> $i {
	my $v = (255 * $i / $bar-width).Int;
	ncplane_set_bg_rgb8($std, $v, 0, 0);
	ncplane_putstr_yx($std, 8, 2 + $i, ' ');
}
ncplane_set_bg_default($std);

# Green gradient
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 10, 2, 'Green:');
for ^$bar-width -> $i {
	my $v = (255 * $i / $bar-width).Int;
	ncplane_set_bg_rgb8($std, 0, $v, 0);
	ncplane_putstr_yx($std, 11, 2 + $i, ' ');
}
ncplane_set_bg_default($std);

# Blue gradient
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 13, 2, 'Blue:');
for ^$bar-width -> $i {
	my $v = (255 * $i / $bar-width).Int;
	ncplane_set_bg_rgb8($std, 0, 0, $v);
	ncplane_putstr_yx($std, 14, 2 + $i, ' ');
}
ncplane_set_bg_default($std);

# Greyscale
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 16, 2, 'Greyscale:');
for ^$bar-width -> $i {
	my $v = (255 * $i / $bar-width).Int;
	ncplane_set_bg_rgb8($std, $v, $v, $v);
	ncplane_putstr_yx($std, 17, 2 + $i, ' ');
}
ncplane_set_bg_default($std);

# Style showcase
ncplane_set_fg_rgb8($std, 180, 180, 180);
ncplane_putstr_yx($std, 19, 2, 'Styles:');
my $sx = 2;
for (NCSTYLE_BOLD, 'Bold'), (NCSTYLE_ITALIC, 'Italic'),
    (NCSTYLE_UNDERLINE, 'Underline'), (NCSTYLE_STRUCK, 'Struck') -> ($style, $name) {
	ncplane_set_fg_rgb8($std, 255, 255, 255);
	ncplane_on_styles($std, $style);
	ncplane_putstr_yx($std, 20, $sx, $name);
	ncplane_off_styles($std, $style);
	$sx += $name.chars + 3;
}

ncplane_set_fg_rgb8($std, 100, 100, 100);
ncplane_putstr_yx($std, $rows - 1, 2, 'Press any key to exit.');

notcurses_render($nc);

my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);
notcurses_stop($nc);
