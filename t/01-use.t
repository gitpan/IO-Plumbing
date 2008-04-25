#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

# test to check that the module loads and is exporting everything we
# want it to

use Test::More no_plan;
use strict;
use warnings;

my @expected = qw( COMMAND_ERROR COMMAND_READY COMMAND_RUNNING
	COMMAND_DONE COMMAND_LOST
	);

ok( !(grep { defined &{$_} } @expected ),
	"didn't imported status constants yet" );

use_ok("IO::Plumbing", ":constants");

ok( !(grep { !defined &{$_} } @expected ), "imported status constants" );

@expected = qw(plumb plug prng bucket vent);

ok( !(grep { defined &{$_} } @expected ), "didn't import tools yet" );

IO::Plumbing->import(":tools");

ok( !(grep { !defined &{$_} } @expected ), "imported tools" );

for my $plugin ( qw(Plug PRNG Vent Bucket Util) ) {
	my $mod = "IO::Plumbing::$plugin";
	Class::Autouse->load($mod);
	pass("Loaded $mod");
}
