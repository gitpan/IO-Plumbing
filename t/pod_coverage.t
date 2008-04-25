#!/usr/bin/perl

use strict;
use warnings;

use Test::Depends qw(Test::Pod::Coverage);

all_pod_coverage_ok
    ( { also_private => [ qr/^[_A-Z]/, "BUILD", "id", "meta",
			], },
      "IO::Plumbing documentation",
    );
