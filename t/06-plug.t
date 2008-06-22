#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

use Test::More no_plan;
use strict;

BEGIN {
	use_ok("IO::Plumbing", qw(plumb plug bucket));
}

my $command = plumb("cat", input => plug, output => bucket);

$command->execute;
my $bucket = $command->terminus;
isa_ok($bucket, "IO::Plumbing::Bucket", "terminus");
is($bucket->contents, "", "Plug - input");

$command = plumb
	( "dd if=/dev/zero bs=1k count=200",
	  output => plug, stderr => "/dev/null",
	);
isnt($command->errormsg, undef, "plug - output");
