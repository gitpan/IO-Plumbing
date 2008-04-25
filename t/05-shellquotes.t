#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

use Test::More;
use strict;
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 0;

my @test_data = grep !/^\s*(#.*)?$/, map { chomp; $_ } <DATA>;

plan(tests => @test_data*2 + 4);

use_ok("IO::Plumbing::Util", "shell_quote", "shell_unquote");

for my $line ( @test_data ) {
	my ($raw, $quoted) = split /\s+\|\|==>\s+/, $line;
	my @ds = eval $raw;
	is(&shell_quote(@ds), $quoted, "shell_quote(".shorten($raw).")");
	my $uq = [&shell_unquote($quoted)];
	is_deeply($uq, \@ds,
		"shell_unquote(".shorten($quoted).")") or do {
		diag("Input: $quoted\n",
		     "Output: ".Dumper($uq),"\n",
		     "Expected: ".Dumper(\@ds));
	};
}

require IO::Plumbing;
my $p = IO::Plumbing::plumb("cat -vent /etc/passwd");
is($p->program, "cat", "shell_unquote (program)");
is_deeply($p->args, [qw"-vent /etc/passwd"], "shell_unquote (args)");
is($p->cmdline, "cat -vent /etc/passwd", "shell_quote");

exit(0);

sub shorten {
	my $what = shift;
	if ( length($what) > 30 ) {
		return substr($what, 0, 27)."...";
	} else {
		return $what;
	}
}

__END__
"blah"         ||==>    blah
"hi'there"     ||==>    hi\'there
'hi"there'     ||==>    'hi"there'
"hi\"the're"   ||==>    hi\"the\'re
"foo>bar"      ||==>    'foo>bar'
"foo>b'ar"     ||==>    foo\>b\'ar
