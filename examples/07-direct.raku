#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native::Types;
use Notcurses::Native::Direct;

# Direct mode demo — prints colored text without taking over the terminal
# Unlike full-screen mode, this works alongside normal shell output

my $ncd = ncdirect_core_init(Str, Pointer, 0)
	or die "Failed to initialize direct mode";
LEAVE { ncdirect_stop($ncd) if $ncd.defined }

# Terminal info
ncdirect_putstr($ncd, 0, "Terminal: {ncdirect_detected_terminal($ncd)}\n");
ncdirect_putstr($ncd, 0, "Size: {ncdirect_dim_x($ncd)}x{ncdirect_dim_y($ncd)}\n");
ncdirect_putstr($ncd, 0, "Palette: {ncdirect_palette_size($ncd)} colors\n");
ncdirect_putstr($ncd, 0, "Truecolor: {ncdirect_cantruecolor($ncd) ?? 'yes' !! 'no'}\n\n");

# Rainbow text
my @text = 'R a i n b o w   T e x t'.comb;
my $len = @text.elems;
for @text.kv -> $i, $ch {
	my $hue = $i / $len * 6;
	my ($r, $g, $b) = do given $hue.Int {
		when 0 { (255, (255 * ($hue - 0)).Int, 0) }
		when 1 { ((255 * (2 - $hue)).Int, 255, 0) }
		when 2 { (0, 255, (255 * ($hue - 2)).Int) }
		when 3 { (0, (255 * (4 - $hue)).Int, 255) }
		when 4 { ((255 * ($hue - 4)).Int, 0, 255) }
		default { (255, 0, (255 * (6 - $hue)).Int) }
	};
	ncdirect_set_fg_rgb8($ncd, $r, $g, $b);
	ncdirect_putstr($ncd, 0, $ch);
}
ncdirect_set_fg_default($ncd);
ncdirect_putstr($ncd, 0, "\n\n");

# Styled text
ncdirect_on_styles($ncd, NCSTYLE_BOLD);
ncdirect_set_fg_rgb8($ncd, 255, 200, 50);
ncdirect_putstr($ncd, 0, "Bold ");
ncdirect_off_styles($ncd, NCSTYLE_BOLD);

ncdirect_on_styles($ncd, NCSTYLE_ITALIC);
ncdirect_set_fg_rgb8($ncd, 50, 200, 255);
ncdirect_putstr($ncd, 0, "Italic ");
ncdirect_off_styles($ncd, NCSTYLE_ITALIC);

ncdirect_on_styles($ncd, NCSTYLE_UNDERLINE);
ncdirect_set_fg_rgb8($ncd, 200, 50, 255);
ncdirect_putstr($ncd, 0, "Underline");
ncdirect_off_styles($ncd, NCSTYLE_UNDERLINE);

ncdirect_set_fg_default($ncd);
ncdirect_putstr($ncd, 0, "\n\n");

# Box drawing
ncdirect_set_fg_rgb8($ncd, 100, 200, 100);
ncdirect_rounded_box($ncd, 0, 0, 0, 0, 3, 30, 0);
ncdirect_putstr($ncd, 0, "\n");
