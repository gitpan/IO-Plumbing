
package IO::Plumbing::PRNG;
use strict;
use base qw(IO::Plumbing);
use Carp;

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	if ( $self->{input} ) {
		if (not ($self->program or $self->code)) {
			$self->program("gpg");
			$self->args("-e", $self->args);
		}
	}
	elsif ( $self->{output} ) {
		if (not ($self->program or $self->code)) {
			$self->program("cat");
			$self->args("/dev/urandom");
		}
	}
}

1;

__END__

=head1 NAME

IO::Plumbing::PRNG - access to entropy

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb prng);


 {
    local($/) = \0;
    while (<$output>) {
       print "Read a filename: '$_'\n";
    }
 }
 $output->wait;

=head1 DESCRIPTION

Degenerate L<IO::Plumbing> object that contains or collects data,
depending on whether it is used as a target or a source of data.

=head1 AUTHOR AND LICENCE

Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

