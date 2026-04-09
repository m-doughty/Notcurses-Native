#!/usr/bin/env raku
use lib 'lib';
use NativeCall;
use Notcurses::Native;
use Notcurses::Native::Types;
use Notcurses::Native::Plane;
use Notcurses::Native::Visual;
use Notcurses::Native::Context;

# Terminal image viewer — displays an image scaled to fit the terminal
# Usage: raku examples/06-imgview.raku <path-to-image>
#        raku examples/06-imgview.raku --pixel <path-to-image>
#   q or Escape to quit

sub MAIN(Str $path, Bool :$pixel = False) {
	die "File not found: $path" unless $path.IO.e;

	my $nc = notcurses_init(NotcursesOptions.new(:flags(NCOPTION_SUPPRESS_BANNERS)), Pointer)
		or die "Failed to initialize notcurses";
	LEAVE { notcurses_stop($nc) if $nc.defined }

	my $std = notcurses_stdplane($nc);
	my uint32 ($rows, $cols);
	ncplane_dim_yx($std, $rows, $cols);

	# Load the image
	my $visual = ncvisual_from_file($path);
	unless $visual.defined {
		notcurses_stop($nc);
		die "Failed to load image: $path (is FFmpeg available?)";
	}

	# Query native image size
	my $geom = Ncvgeom.new;
	my $probe = NcvisualOptions.new(:scaling(NCSCALE_NONE), :blitter(NCBLIT_1x1));
	ncvisual_geom($nc, $visual, $probe, $geom);
	my $img-w = $geom.pixx;
	my $img-h = $geom.pixy;

	# Determine blitter: pixel if requested/supported, otherwise best available
	my $pixel-ok = notcurses_check_pixel_support($nc);
	my $blitter;
	my $blitter-name;

	if $pixel || $pixel-ok > 0 {
		$blitter = NCBLIT_PIXEL;
		$blitter-name = 'pixel';
	} else {
		$blitter = ncvisual_media_defblitter($nc, NCSCALE_SCALE);
		$blitter-name = notcurses_str_blitter($blitter) // 'unknown';
	}

	# Create a plane for the image (must be child of stdplane to composite)
	my $img-plane = ncplane_create($std, NcplaneOptions.new(:y(0), :x(0), :rows($rows - 1), :cols($cols)));

	# Blit onto our plane
	my $vopts = NcvisualOptions.new(:scaling(NCSCALE_SCALE), :blitter($blitter));
	$vopts.set-plane($img-plane);

	my $result = ncvisual_blit($nc, $visual, $vopts);

	# Fall back through blitters if the chosen one fails
	if !$result.defined && $blitter == NCBLIT_PIXEL {
		$blitter = ncvisual_media_defblitter($nc, NCSCALE_SCALE);
		$blitter-name = notcurses_str_blitter($blitter) // 'fallback';
		$vopts = NcvisualOptions.new(:scaling(NCSCALE_SCALE), :blitter($blitter));
		$vopts.set-plane($img-plane);
		$result = ncvisual_blit($nc, $visual, $vopts);
	}

	if !$result.defined {
		$vopts = NcvisualOptions.new(:scaling(NCSCALE_SCALE), :blitter(NCBLIT_1x1));
		$vopts.set-plane($img-plane);
		$result = ncvisual_blit($nc, $visual, $vopts);
		$blitter-name = '1x1';
	}

	unless $result.defined {
		notcurses_stop($nc);
		die "Failed to render image";
	}

	# Status bar
	ncplane_set_fg_rgb8($std, 180, 180, 180);
	ncplane_set_bg_rgb8($std, 30, 30, 30);
	my $status = " {$path.IO.basename}  {$img-w}x{$img-h}  [{$blitter-name}]  q to quit ";
	ncplane_putstr_yx($std, $rows - 1, 0, $status ~ (' ' x max(0, $cols - $status.chars)));
	ncplane_set_bg_default($std);

	notcurses_render($nc);

	# Wait for q or Escape
	loop {
		my $ni = Ncinput.new;
		notcurses_get_blocking($nc, $ni);
		last if $ni.id == 'q'.ord || $ni.id == NCKEY_ESC;
	}

	ncplane_destroy($img-plane);
	ncvisual_destroy($visual);
}
