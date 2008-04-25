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

my
 $command = plumb("cat", args => [qw(-e)], input => $0);
 $command->output(plumb("od", args => ["-x"]));

$command->execute;
like($command->terminus->contents, qr/^.*2123 752f 7273 622f/, "Bucket");

IO::Plumbing->import("bucket");
$command = plumb("cat", args => ["-e"], input => bucket("foo\n"));

$command->execute;
my $output = $command->terminus->contents;
like($output, qr/foo\$/, "pouring bucket");

# pour line by line
my $bukkit = bucket(undef, input => plumb(sub { print "O HAI\n$$\n" }));

$bukkit->execute;
my $line = $bukkit->getline;
is($line, "O HAI\n", "read from child process");
ok($bukkit->pid, "started a subprocess");
chomp($line = $bukkit->getline);
is($line, $bukkit->pid, "read its PID");
ok(!$bukkit->getline, "readline at eof");
