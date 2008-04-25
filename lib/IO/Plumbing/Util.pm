
package IO::Plumbing::Util;

use strict;
use base qw(Exporter);
use Carp qw(croak);

BEGIN {
	our @EXPORT_OK = qw(shell_quote shell_unquote);
}

# very paranoid shellquote that should not let anything untoward
# through.
sub shell_quote {
	return join(" ", map {
		my $x = $_;
		croak "you're weren't really going to try to put that "
			."in an char**, were you?" if m{\0};
		# single quote anything without quotes,
		# or escape anything except a shortlist of OK chars
		if ( $x =~ m{'} ) {
			$x =~ s{([^\w!%+,\-./:@^])}{\\$1}g;
		}
		elsif ( $x =~ m{[^\w%+,\-./:@^]} ) {
			$x =~ s{(.*)}{'$1'};
		}
		$x;
	} @_);
}

# little func to undo shellquoting
sub shell_unquote {
	my @rv;
	my $accum;
	my $ok;
	$_[0]=~m{^\s*}g;
	while ( $_[0] =~ m{\G(?: '([^']*)'    # $tok[0] - single quotes
			| "((?:\\.|[^"])*)"   # $tok[1] - double quotes
			| ([^"'\s\\]+)        # $tok[2] - regular chars
			| \\(.)               # $tok[3] - escaped chars
			| (\s+)               # $tok[4] - word boundary
			| ()$                 # $tok[5] - end of line
			)}xg ) {
		my @tok = ($1, $2, $3, $4, $5, $6);
		if ( defined $tok[1] ) {
			$tok[1] =~ s{\\(.)}{$1}g;
		}
		if ( $tok[4] ) {
			push @rv, $accum;
			undef($accum);
		}
		elsif ( defined $tok[5] ) {
			$ok = 1;
		}
		elsif ( (my $frag) = grep { defined } @tok ) {
			$accum = (defined $accum ? $accum : "").$frag;
		}
		else {
			croak "bad input to shell_unquote: `$_[0]' at pos"
				.pos($_[0]);
		}
	}

	if ( defined $accum ) {
		push @rv, $accum
	}

	@rv;
}

1;

__END__

=head1 NAME

IO::Plumbing::Util - freebies in the bag

=head1 SYNOPSIS

 use IO::Plumbing::Util qw(shell_quote shell_unquote);

 my $bad_fn = q{pw"`sudo rm -rf *`"n3d};

 print shell_quote($bad_fn);  # pw\"\`\ sudo\ rm\ \-rf\ \*\`\"n3d

 print shell_unquote(shell_quote($bad_fn));  # identity, we hope ;)

=head1 DESCRIPTION

A couple of small functions for turning command line arguments into
something which you can safely paste back into the shell to run, even
in the face of arbitrary weird rubbish.

=head1 FUNCTIONS

=over

=item shell_quote(@args)

Returns a string which should be safe for saving, through X buffers,
and later decoding with a Bourne Shell or C<shell_unquote>.

=item shell_unquote($string)

Returns a list.  Of course there are many inputs the shell would
consider a special character where this module blithely lets it
through.

=back

=head1 AUTHOR AND LICENCE

Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

