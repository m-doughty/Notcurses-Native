#!/usr/bin/env raku

# Keep native-bundle attribution aligned before the binary recipe is tagged.
sub parse-json(Str $text) { Rakudo::Internals::JSON.from-json($text) }
sub tokens(Str $text --> List) {
	$text.match(/ '"' [ '\\' . | <-["\\]> ]* '"' | <[{}\[\]:,]> /, :g).List;
}
sub replace-version(Str $text, Str $version --> Str) {
	my @tokens = tokens($text);
	my $depth = 0;
	my @values;
	for @tokens.kv -> $i, $token {
		my $value = $token.Str;
		if $value eq any('{', '[') { $depth++ }
		elsif $value eq any('}', ']') { $depth-- }
		elsif $depth == 1 && $value.starts-with('"') && parse-json($value) eq 'version'
			&& $i + 2 < @tokens && @tokens[$i + 1].Str eq ':' {
			@values.push(@tokens[$i + 2]);
		}
	}
	die 'Expected exactly one direct string version field' unless @values.elems == 1
		&& @values[0].Str.starts-with('"');
	my $value = @values[0];
	$text.substr(0, $value.from) ~ '"' ~ $version ~ '"' ~ $text.substr($value.to);
}
sub own-component-span(Str $text --> List) {
	my @starts;
	my @found;
	for tokens($text) -> $token {
		if $token.Str eq '{' { @starts.push($token.from) }
		elsif $token.Str eq '}' {
			my $start = @starts.pop;
			my $part = $text.substr($start, $token.to - $start);
			my $object = parse-json($part);
			@found.push([$start, $token.to]) if ($object<id> // '') eq 'notcurses-native';
		}
	}
	die 'Expected exactly one notcurses-native component object' unless @found.elems == 1;
	@found[0].List;
}
sub MAIN(Str $version) {
	die 'Version must contain digits separated by dots'
		unless $version ~~ /^ <[0..9]>+ [ '.' <[0..9]>+ ]* $/;
	my $root = $*PROGRAM.absolute.IO.parent.parent.parent;
	my @paths = $root.add('META6.json'), $root.add('resources/third-party.json');
	for @paths -> $path { die "Expected a regular input file: $path" unless $path.f && !$path.l }
	my @old = @paths.map(*.slurp);
	my $meta = parse-json(@old[0]);
	my $manifest = parse-json(@old[1]);
	die 'Expected Notcurses::Native metadata with a string version'
		unless $meta ~~ Associative && ($meta<name> // '') eq 'Notcurses::Native'
		&& $meta<version> ~~ Str;
	die 'Expected a components array' unless $manifest ~~ Associative && $manifest<components> ~~ Positional;
	my @own = $manifest<components>.grep({ $_ ~~ Associative && ($_<id> // '') eq 'notcurses-native' });
	die 'Expected exactly one notcurses-native component with a string version'
		unless @own.elems == 1 && @own[0]<version> ~~ Str;
	my ($start, $end) = own-component-span(@old[1]);
	my @new = replace-version(@old[0], $version),
		@old[1].substr(0, $start)
		~ replace-version(@old[1].substr($start, $end - $start), $version)
		~ @old[1].substr($end);
	# Validate both complete documents before replacing either input.
	parse-json($_) for @new;
	my %temps;
	LEAVE { .unlink for %temps.values.grep(*.e) }
	for @paths.kv -> $i, $path {
		next if @old[$i] eq @new[$i];
		my $temp = $path.parent.add(".sync-version-{$*PID}-{(^2**60).pick}-$i.tmp");
		$temp.spurt(@new[$i], :createonly);
		%temps{$i} = $temp;
	}
	for @paths.kv -> $i, $path {
		next if @old[$i] eq @new[$i];
		%temps{$i}.rename($path);
	}
	say "Release metadata and native attribution agree on $version";
}
