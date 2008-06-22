#!/usr/bin/perl -w
#
# Copyright 2007, 2008, Sam Vilain.  All Rights Reserved.  This
# program is free software; you can use it and/or modify it under the
# same terms as Perl itself.
#

use Test::More no_plan;
use strict;

BEGIN {
	use_ok("IO::Plumbing", qw(plumb bucket hose));
}

use IO::Plumbing qw(plumb hose);

# catch stderr from that command!
my $cat = plumb("cat", output => bucket);

my $hose = hose;
ok($hose, "made a host");
$cat->input($hose);
$cat->execute();
pass("Executed contraption");

ok($hose->print("Hello, world\n"), "put into hose");
$hose->close;

my $line = $cat->terminus->getline;
is($line, "Hello, world\n", "Passed through ok");

