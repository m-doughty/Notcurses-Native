#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;

# Simplest notcurses program: display centered text, wait for keypress

my $nc = notcurses_init(NotcursesOptions.new, Pointer)
	or die "Failed to initialize notcurses";

my $std = notcurses_stdplane($nc);
my uint32 ($rows, $cols);
ncplane_dim_yx($std, $rows, $cols);

# Center the message
my $msg = 'Hello from Notcurses::Native!';
my $y = ($rows / 2).Int;
my $x = (($cols - $msg.chars) / 2).Int;

ncplane_set_fg_rgb8($std, 0, 255, 128);
ncplane_putstr_yx($std, $y, $x, $msg);

ncplane_set_fg_rgb8($std, 128, 128, 128);
ncplane_putstr_yx($std, $y + 2, ($cols - 22) div 2, 'Press any key to exit.');

notcurses_render($nc);

# Wait for a keypress
my $ni = Ncinput.new;
notcurses_get_blocking($nc, $ni);

notcurses_stop($nc);
