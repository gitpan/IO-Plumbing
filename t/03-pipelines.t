#!/usr/bin/perl -w
#
# Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
# free software; you can use it and/or modify it under the same terms as
# Perl itself.
#

use Test::More no_plan;
use strict;

BEGIN {
	use_ok("IO::Plumbing", qw(plumb));
}

my $command = plumb();

 # input plumbing - connects FHs before running
 $command->program("cat");
 $command->args(["-e", "-n"]);
 $command->input($0);

 # similar style to open(my $fh, "command|")
 $command->execute;
 my $fh = $command->terminus->in_fh;
 my $output = join("", <$fh>);

 $command->wait;

is($command->rc, 0, "cat worked");
is($command->errormsg, "finished normally", "->errormsg");
like($output, qr/\Q<+=- W00T -=+>\E/, "can read from output FH");

 # another way to connect pipelines
 $command = plumb("cat", args => [qw(-e)], input => $0);
 $command->output(plumb("od", args => ["-x"]));

 # as traditional, we start from the beginning and wait
 # on the command at the end of the chain.
 $command->execute;
 $fh = $command->terminus->in_fh;
 $output = join("", <$fh>);

$command->terminus->wait;

is($command->terminus->rc, 0, "pipeline worked");
is($command->terminus->errormsg, "finished normally", "->errormsg");
like($output, qr/^.*(2123|2321)\s+(752f|2f75)\s+(7273|7372)\s+(622f|2f62)/i,
     "pipeline worked");
