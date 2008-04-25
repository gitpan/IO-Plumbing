
package IO::Plumbing::Plug;
use strict;
use base qw(IO::Plumbing);
use Carp qw(croak);

#sub default_input { "/dev/null" }
#sub default_output { "/dev/full" }
sub default_input { undef }
sub default_output { undef }
sub default_stderr { undef }

sub output {
	my $self = shift;
	if ( @_ and $self->input ) {
		croak "tried to set output of Plug with input";
	}
	else {
		$self->SUPER::output(@_);
	}
}

sub input {
	my $self = shift;
	if ( @_ and $self->output ) {
		croak "tried to set input of Plug with output";
	}
	else {
		$self->SUPER::input(@_);
	}
}

sub _open_input {
	my $self = shift;
	if ( $self->input ) {
		open our $full, ">/dev/full" unless $full;
		warn "$self: FH ".fileno($full)." is full, connecting "
			."to $self->{input}\n" if IO::Plumbing::DEBUG &&
				IO::Plumbing::DEBUG gt "1";
		$self->{input}->out_fh($full);
	}
}

sub _open_output {
	my $self = shift;
	my $which = shift;

	if ( my $plumb = $self->$which ) {
		open our $null, "</dev/null" unless $null;
		warn "$self: FH ".fileno($null)." is null, connecting "
			."to $plumb\n" if IO::Plumbing::DEBUG &&
				IO::Plumbing::DEBUG gt "1";
		$plumb->in_fh($null);
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

