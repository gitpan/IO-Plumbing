
package IO::Plumbing::Plug;
use strict;
use IO::Plumbing qw(:constants);
use base qw(IO::Plumbing);
use Scalar::Util qw(blessed);

use Carp qw(croak);

sub default_input { undef }
sub default_output { undef }
sub default_stderr { "/dev/null" }

sub output {
	my $self = shift;
	if ( @_ and $self->has_input ) {
		croak "tried to set output of Plug with input";
	}
	else {
		$self->SUPER::output(@_);
	}
}

sub input {
	my $self = shift;
	if ( @_ and $self->has_output ) {
		croak "tried to set input of Plug with output";
	}
	else {
		$self->SUPER::input(@_);
	}
}

sub get_fd_pair {
	my $self = shift;
	my $direction = $self->_parse_direction(shift);

	if ( $direction ) {
		open my $null, "</dev/null";
		warn "$self: FH ".fileno($null)." is <null\n"
			if IO::Plumbing::DEBUG && IO::Plumbing::DEBUG gt "1";
		$null;
	}
	else {
		open my $full, ">/dev/full";
		warn "$self: FH ".fileno($full)." is >full\n"
			if IO::Plumbing::DEBUG && IO::Plumbing::DEBUG gt "1";
		$full;
	}
}

sub needs_fork { 0 }

1;

__END__

=head1 NAME

IO::Plumbing::Plug - stop data flowing

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb bucket plug);

 # plug that input!  that's actually the default.
 my $output = plumb("find / -print0", input => plug)
                ->output->raw_fh;

 {
    local($/) = \0;
    while (<$output>) {
       print "Read a filename: '$_'\n";
    }
 }
 $output->wait;

=head1 DESCRIPTION

Degenerate L<IO::Plumbing> object that returns end of file or device
full depending on whether it is used as a source or target of data.

=head1 AUTHOR AND LICENCE

Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

