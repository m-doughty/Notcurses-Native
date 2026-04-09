#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Channel;
use Notcurses::Native::Widgets;

# Animated progress bars with the ncprogbar widget

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";
LEAVE { notcurses_stop($nc) if $nc.defined }

my $std = notcurses_stdplane($nc);
my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);

ncplane_set_fg_rgb8($std, 200, 200, 200);
ncplane_putstr_yx($std, 1, 2, 'Progress Bar Demo');
ncplane_set_fg_rgb8($std, 100, 100, 100);
ncplane_putstr_yx($std, $rows - 1, 2, 'Simulating work...');

# Create 4 progress bars with different color schemes
my @bars;
my @names = ('Download  ', 'Processing', 'Uploading ', 'Verifying ');
my @colors = (
	(0x00AA00, 0x00FF00, 0x004400, 0x008800),  # green
	(0x0000AA, 0x0000FF, 0x000044, 0x000088),  # blue
	(0xAA0000, 0xFF0000, 0x440000, 0x880000),  # red
	(0xAAAA00, 0xFFFF00, 0x444400, 0x888800),  # yellow
);

my $bar-width = min($cols - 20, 50);

for ^4 -> $i {
	my $y = 4 + $i * 3;
	ncplane_set_fg_rgb8($std, 180, 180, 180);
	ncplane_putstr_yx($std, $y, 2, @names[$i]);

	my $plane = ncplane_create($std, NcplaneOptions.new(
		:y($y), :x(14), :rows(1), :cols($bar-width),
	));
	my ($ul, $ur, $bl, $br) = @colors[$i].map(*.Int);
	my $opts = NcprogbarOptions.new(
		:ulchannel($ul), :urchannel($ur),
		:blchannel($bl), :brchannel($br),
	);
	my $bar = ncprogbar_create($plane, $opts);
	ncprogbar_set_progress($bar, 0e0);
	@bars.push: ($bar, $plane);
}

# Animate at different speeds
my @speeds = (0.012, 0.008, 0.015, 0.005);
my @progress = (0e0, 0e0, 0e0, 0e0);
my $all-done = False;

until $all-done {
	# Check for keypress
	my $ni = Ncinput.new;
	my $key = notcurses_get_nblock($nc, $ni);
	last if $key > 0 && ($ni.id == 'q'.ord || $ni.id == NCKEY_ESC);

	$all-done = True;
	for ^4 -> $i {
		if @progress[$i] < 1e0 {
			@progress[$i] = min(1e0, @progress[$i] + @speeds[$i] * (1 + rand * 0.5));
			ncprogbar_set_progress(@bars[$i][0], @progress[$i]);
			$all-done = False;
		}
		# Percentage label
		my $pct = (@progress[$i] * 100).Int.fmt('%3d%%');
		ncplane_set_fg_rgb8($std, 200, 200, 200);
		ncplane_putstr_yx($std, 4 + $i * 3, 14 + $bar-width + 1, $pct);
	}

	notcurses_render($nc);
	sleep 0.03;
}

ncplane_set_fg_rgb8($std, 100, 255, 100);
ncplane_putstr_yx($std, $rows - 1, 2, 'All done! Press any key to exit.     ');
notcurses_render($nc);

my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);

for @bars -> ($bar, $plane) {
	ncprogbar_destroy($bar);
}
