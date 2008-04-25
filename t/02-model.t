#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

use Test::More no_plan;
use strict;
use Scalar::Util qw(weaken);

BEGIN {
	use_ok("IO::Plumbing", qw(plumb plug));
}

 my $command = IO::Plumbing->new
     ( program => "echo",
       args    => [ "Hello,",  "world" ],
     );

is($command->program, "echo", "->program mutator");
is_deeply($command->args, ["Hello,", "world"] , "->args mutator");
is($command->status_name, "ready", "->status_name");

 # input plumbing - connects FHs before running
 $command->program("cat");
 $command->args(["-e", "-n"]);
 $command->input("filename");

is($command->input, "filename", "->input");

my $command2 = plumb("foo");
$command2->input($command);

is($command->output(), $command2, "double-linking via input");
is($command2->input(), $command, "double-linking via input (2)");

$command = plumb("bar");
$command2->output($command);
is($command->input(), $command2, "double-linking via output");
is($command2->output(), $command, "double-linking via output (2)");
isnt($command2->stderr(), $command, "double-linking via output (3)");

$command = plumb("baz");
$command2->stderr($command);
is($command->input(), $command2, "double-linking via stderr");
isnt($command2->output(), $command, "double-linking via stderr (2)");
is($command2->stderr(), $command, "double-linking via stderr (3)");

like($command, qr/\bbaz\b/, "stringify cmdline");

my $ref = $command;
weaken($ref);
undef($_) for ($command,$command2);
is($ref, undef, "didn't leak");

my $plug = plug;
$command = plumb("cat", output => $plug);
weaken($plug);

ok($command->output, "plumb output to plug");
is($command->output->input, $command, "plug double-linking");

weaken($command);

ok( (!$plug && !$command), "leaktest");
