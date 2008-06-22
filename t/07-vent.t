#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

use Test::More no_plan;
use strict;

BEGIN {
	use_ok("IO::Plumbing", qw(plumb vent bucket));
}

my $command = plumb("cat", input => vent);

$command->terminus->collect_max(1000);

$command->execute;
{
my @warnings;
local($SIG{__WARN__})=sub{push @warnings, @_};
like($command->terminus->contents, qr/\0{1000}/, "Vent - input");
is_deeply(\@warnings, 
	  ["bucket(filling): not spooling more than 1000 bytes from `cat`\n"],
	  "got some warnings!");
}

my $bucket = bucket;
$command = plumb
	("dd bs=1k count=200",
	 input => vent, output => $bucket,
	 stderr => vent);

$command->execute;
$bucket->collect_out;
like($bucket->contents, qr{\A\0{1000}}, "saw lots of nothing");
is($command->error, undef, "vent - success");
is($command->rc, 0, "vent - success (RC)");
