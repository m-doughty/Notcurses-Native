#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Channel;

# Draw various box styles with labels and colors

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";

my $std = notcurses_stdplane($nc);

sub draw-labeled-box($parent, $y, $x, $rows, $cols, $label, $fg-r, $fg-g, $fg-b, &box-fn) {
	my $plane = ncplane_create($parent, NcplaneOptions.new(:$y, :$x, :$rows, :$cols));
	ncplane_set_fg_rgb8($plane, $fg-r, $fg-g, $fg-b);

	my uint64 $channels = 0;
	ncchannels_set_fg_rgb($channels, ($fg-r +< 16) +| ($fg-g +< 8) +| $fg-b);
	box-fn($plane, 0, $channels, $rows - 1, $cols - 1, 0);

	# Label inside box
	ncplane_set_fg_rgb8($plane, 255, 255, 255);
	ncplane_putstr_yx($plane, 1, 2, $label);
	$plane
}

my @planes;

@planes.push: draw-labeled-box($std, 1, 2, 5, 24, 'Rounded Box',
	100, 200, 255, -> $n, $s, $c, $yr, $xr, $ctl { ncplane_rounded_box($n, $s, $c, $yr, $xr, $ctl) });

@planes.push: draw-labeled-box($std, 1, 28, 5, 24, 'Double Box',
	255, 200, 100, -> $n, $s, $c, $yr, $xr, $ctl { ncplane_double_box($n, $s, $c, $yr, $xr, $ctl) });

@planes.push: draw-labeled-box($std, 1, 54, 5, 24, 'ASCII Box',
	200, 255, 100, -> $n, $s, $c, $yr, $xr, $ctl { ncplane_ascii_box($n, $s, $c, $yr, $xr, $ctl) });

@planes.push: draw-labeled-box($std, 8, 2, 5, 24, 'Light Box',
	255, 100, 200, -> $n, $s, $c, $yr, $xr, $ctl {
		ncplane_rounded_box($n, $s, $c, $yr, $xr, $ctl)
	});

@planes.push: draw-labeled-box($std, 8, 28, 5, 24, 'Bold + Blue BG',
	255, 255, 0, -> $n, $s, $c, $yr, $xr, $ctl {
		ncplane_on_styles($n, NCSTYLE_BOLD);
		ncplane_set_bg_rgb8($n, 0, 0, 80);
		ncplane_double_box($n, $s, $c, $yr, $xr, $ctl);
		ncplane_off_styles($n, NCSTYLE_BOLD);
		ncplane_set_bg_default($n);
	});

# Nested boxes
my $outer = ncplane_create($std, NcplaneOptions.new(:y(15), :x(2), :rows(9), :cols(40)));
ncplane_set_fg_rgb8($outer, 255, 100, 100);
ncplane_rounded_box($outer, 0, 0, 8, 39, 0);
ncplane_set_fg_rgb8($outer, 255, 255, 255);
ncplane_putstr_yx($outer, 0, 2, ' Nested ');

my $inner = ncplane_create($outer, NcplaneOptions.new(:y(2), :x(3), :rows(5), :cols(34)));
ncplane_set_fg_rgb8($inner, 100, 255, 100);
ncplane_double_box($inner, 0, 0, 4, 33, 0);
ncplane_set_fg_rgb8($inner, 200, 200, 200);
ncplane_putstr_yx($inner, 2, 4, 'Planes can be nested!');
@planes.push: $outer;
@planes.push: $inner;

my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);
ncplane_set_fg_rgb8($std, 100, 100, 100);
ncplane_putstr_yx($std, $rows - 1, 2, 'Press any key to exit.');

notcurses_render($nc);

my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);

ncplane_destroy($_) for @planes.reverse;
notcurses_stop($nc);
