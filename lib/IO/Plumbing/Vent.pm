
package IO::Plumbing::Vent;
use strict;
use base qw(IO::Plumbing);
use Carp;

sub default_input { undef }
sub default_output { undef }
sub default_stderr { undef }

sub blowing {
	my $self = shift;
	return !!$self->output;
}

sub venting {
	my $self = shift;
	return !!$self->input;
}

sub output {
	my $self = shift;
	if ( @_ and $self->venting ) {
		croak "tried to set output of Vent with input";
	}
	else {
		my $output = $self->SUPER::output(@_);
		if ( $output and @_ ) {
			$self->_open_output("output");
		}
		$output;
	}
}

sub input {
	my $self = shift;
	if ( @_ and $self->output ) {
		croak "tried to set input of Vent with output";
	}
	else {
		my $input = $self->SUPER::input(@_);
		if ( $input and @_ ) {
			$self->_open_input;
		}
		$input;
	}
}

sub in_fh {
	my $self = shift;
	if ( $self->blowing ) {
		return undef;
	} else {
		$self->SUPER::in_fh(@_);
	}
}

sub out_fh {
	my $self = shift;
	if ( $self->venting ) {
		return undef;
	} else {
		$self->SUPER::out_fh(@_);
	}
}

sub needs_fork {
	0;  # on unix, anyway
}

sub name {
	my $self = shift;
	if ( $self->blowing ) {
		return "vent(blowing)";
	}
	else {
		return "vent(venting)";
	}

}

sub get_fd_pair {
	my $self = shift;
	my $direction = shift;

	if ( $direction ) {
		open my $zero, "</dev/zero";
		warn "$self: FH ".fileno($zero)." is <zero\n"
			if IO::Plumbing::DEBUG && IO::Plumbing::DEBUG gt "1";
		$zero;
	}
	else {
		open my $null, ">/dev/null";
		warn "$self: FH ".fileno($null)." is >null\n"
			if IO::Plumbing::DEBUG && IO::Plumbing::DEBUG gt "1";
		$null;
	}
}

1;

__END__

=head1 NAME

IO::Plumbing::Vent - lets data flow freely away somewhere harmless

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb vent);

 # ignore stderr from that command!
 my $output = plumb(program => "find", args=>[qw"/ -print0"],
                    stderr => vent);

 {
    local($/) = \0;
    while (<$output>) {
       print "Read a filename: '$_'\n";
    }
 }
 $output->wait;

=head1 DESCRIPTION

Degenerate L<IO::Plumbing> object.

=head1 WARNING

This module has no tests!

=head1 AUTHOR AND LICENCE

Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

