
package IO::Plumbing::Hose;
use strict;
use IO::Plumbing qw(:constants);
use base qw(IO::Plumbing);
use Carp;

sub sucking {
	my $self = shift;
	return !!$self->output;
}

sub gushing {
	my $self = shift;
	return !!$self->input;
}

sub output {
	my $self = shift;
	if ( @_ and $self->gushing ) {
		croak "tried to set output of Hose with input";
	}
	elsif ( @_ ) {
		my $output = $self->SUPER::output(@_);
		$self->{status} = ($self->{contents} ? COMMAND_READY
				   : COMMAND_ERROR);
		$output;
	}
	else {
		$self->SUPER::output(@_);
	}
}

sub default_output {
	undef;
}

sub default_input {
	undef;
}

sub input {
	my $self = shift;
	if ( @_ and $self->sucking ) {
		croak "tried to set input of Hose with output";
	}
	else {
		$self->SUPER::input(@_);
	}
}

sub in_fh {
	my $self = shift;
	if ( $self->gushing ) {
		$self->SUPER::in_fh(@_);
	} else {
		return undef;
	}
}

sub out_fh {
	my $self = shift;
	if ( $self->sucking ) {
		$self->SUPER::out_fh(@_);
	} else {
		return undef;
	}
}

sub needs_fork {
	0;
}

sub needs_pipe {
	1;
}

sub name {
	my $self = shift;
	if ( $self->gushing ) {
		return "hose(gushing)";
	}
	elsif ( $self->sucking ) {
		return "hose(sucking)";
	}
	else {
		return "hose(new)";
	}
}

sub getline {
	my $self = shift;
	if ( $self->sucking ) {
		croak "tried to read from a sucking hose";
	}
	else {
		return $self->in_fh->getline(@_);
	}
}

sub print {
	my $self = shift;
	if ( $self->gushing ) {
		croak "tried to put into a gushing hose";
	}
	else {
		return $self->out_fh->print(@_);
	}

}

sub close {
	my $self = shift;
	if ( $self->gushing ) {
		$self->in_fh->close;
	}
	elsif ( $self->sucking ) {
		$self->out_fh->close;
	}
	else {
		croak "tried to close a lonely hose";
	}
}

1;

__END__

=head1 NAME

IO::Plumbing::Hose - handles that plug into IO::Plumbing pipelines

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb hose);

 # catch stderr from that command!
 my $cat = plumb("cat", output => hose);

 my $hose = hose;
 $cat->input($hose);
 $cat->execute();

 $hose->print "Hello, world\n";
 $hose->close;

 # or just grab the FH and wrangle it yourself
 my $handle = $hose->out_fh;

 print { $handle } "Hello, world";
 close($handle);

 # and read from it!
 print $cat->terminus->getline;  # "Hello, world\n";

=head1 DESCRIPTION

The hose is an interface to IO::Plumbing pipelines that effectively
give you a "raw" unidirectional filehandle.

=head1 METHODS

=over

=item $hose->gushing

A "gushing" hose is one that has something attached to its input.  It
gushes data.

=item $hose->sucking

A "sucking" hose is one that has something attached to its output.
There is a process on the other end which is (hopefully) sucking data.

=back

=head1 AUTHOR AND LICENCE

Copyright 2008, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

