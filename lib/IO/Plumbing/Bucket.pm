
package IO::Plumbing::Bucket;
use strict;
use IO::Plumbing qw(:constants);
use base qw(IO::Plumbing);
use Carp;

sub pouring {
	my $self = shift;
	return !!$self->output;
}

sub filling {
	my $self = shift;
	return !!$self->input;
}

sub output {
	my $self = shift;
	if ( @_ and $self->filling ) {
		croak "tried to set output of Bucket with input";
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
	if ( @_ and $self->pouring ) {
		croak "tried to set input of Bucket with output";
	}
	else {
		$self->SUPER::input(@_);
	}
}

sub in_fh {
	my $self = shift;
	if ( $self->pouring ) {
		return undef;
	} else {
		$self->SUPER::in_fh(@_);
	}
}

sub out_fh {
	my $self = shift;
	if ( $self->filling ) {
		return undef;
	} else {
		$self->SUPER::out_fh(@_);
	}
}

sub needs_fork {
	my $self = shift;
	$self->pouring;
}

sub needs_pipe { 1 }

sub execute {
	my $self = shift;

	if ( $self->filling ) {
		return $self->get_plumb(0, 0)->execute();
	}
	elsif ( $self->pouring ) {
		$self->code(sub { print $self->contents });
		$self->SUPER::execute();
	}
	else {
		confess "tried to execute a bucket.";
	}
}

sub name {
	my $self = shift;
	if ( $self->filling ) {
		return "bucket(filling)";
	}
	else {
		return "bucket(pouring)";
	}
}

sub wait {
	my $self = shift;
	if ( $self->filling ) {
		$self->collect_out;
		$self->input->wait;
	}
	else {
		$self->SUPER::wait(@_);
	}
}

sub contents {
	my $self = shift;
	if ( @_ ) {
		$self->{contents} = shift;
		if ( $self->pouring ) {
			$self->{STATUS} = COMMAND_READY;
		}
	}
	else {

		if ( $self->filling ) {
			$self->execute unless $self->done;
			$self->{contents}||=[];
			$self->wait;
		}

		if ( wantarray ) {
			if ( ref $self->{contents} eq "ARRAY" ) {
				@{ $self->{contents} };
			}
			elsif ( ref $self->{contents} eq "SCALAR" ) {
				${$self->{contents}};
			}
		}
		else {
			if ( ref $self->{contents} eq "ARRAY" ) {
				$self->{contents} =
					\(join("", @{ $self->{contents} }));
			}
			${$self->{contents}};
		}
	}
}

BEGIN {
	no strict 'refs';
	for my $func ( qw(status done rc pid error errormsg)) {
		my $SUPER = "SUPER::$func";
		*$func = sub {
			my $self = shift;
			if ( $self->filling ) {
				warn "$self asking ".$self->input
					." for $func\n"
					if IO::Plumbing::DEBUG
						&& IO::Plumbing::DEBUG ge "1";
				$self->input->$func;
			}
			else {
				$self->$SUPER;
			}
		};
	}
}

sub collect_out {
	my $self = shift;
	return if $self->{collected};

	my $out_b = $self->{contents}||=[];
	my $x;
	if ( ref $out_b and ref $out_b eq "ARRAY" ) {
		$x = $out_b;
	} else {
		$x = [];
	}

	warn "$self: about to collect\n"
		if IO::Plumbing::DEBUG and IO::Plumbing::DEBUG gt "1";

	my $spool_fh = $self->get_fd(0)
		or die "bucket $self has no FD 0";

	my $spooled = 0;
	my $max = $self->collect_max;
	my $buffer;
	my $block_size = (stat $spool_fh)[11] || 2**12;
	my $read;

	warn "$self: collecting from FD ".fileno($spool_fh)."\n"
		if IO::Plumbing::DEBUG;

	while ( $read = sysread $spool_fh, $buffer, $block_size ) {

		last if !length $buffer;
		$spooled += length $buffer;
		push @$x, $buffer;

		if ( $max and $spooled > $max) {
			warn "$self: not spooling more than $max bytes from "
				."`".$self->input->cmdline."`\n";
			last;
		}
	}

	close $spool_fh;
	$self->{collected} = 1;

	if ( ref $out_b eq "SCALAR" ) {
		$$out_b = join "", @$x;
	}
	elsif ( ref $out_b eq "ARRAY" ) {
		@$out_b = @$x;
	}

	$out_b;
}

sub collect_max {
	my $self = shift;
	if ( @_ ) {
		$self->{collect_max} = shift;
	}
	$self->{collect_max};
}

sub getline {
	my $self = shift;
	if ( $self->pouring ) {
		croak "tried to read from a pouring bucket";
	}
	else {
		return $self->in_fh->getline(@_);
	}
}

1;

__END__

=head1 NAME

IO::Plumbing::Bucket - catch (or pour in) data

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb bucket);

 # catch stderr from that command!
 my $find = plumb("find", args=>[qw"/ -print0"],
                  stderr => bucket);

 # uses $var as a buffer
 my $var;
 my $bucket = bucket($var);

 # array-based buffer
 $bucket = bucket([]);

 # instead of letting the bucket catch everything, you can read from
 # it on its own.
 $bucket->getline;

 # array-based buffer

=head1 DESCRIPTION

Degenerate L<IO::Plumbing> object that contains or collects data,
depending on whether it is used as a target or a source of data.

Note that there are IPC issues with multiple target buckets that the
first version of L<IO::Plumbing> considers out of scope.

=head1 METHODS

=over

=item collect_max( [ $value ] )

Specify the maximum size of data that will be collected in the output
buffer before the filehandle is closed.  Defaults to B<unlimited>.

=back

=head1 NOTES

=head2 PIPING LOTS INTO A BUCKET

L<IO::Plumbing::Bucket> objects are the same for each time it is used
in a pipeline, though it is possible to have multiple pipes emptying
into one bucket.

For example, you can point the STDERR of a whole pipeline of processes
into the same bucket; unless your pipelines start buffering (say,
about 8kB written per scheduler context switch round) or some silly
program starts doing buffered I/O on its STDERR (or making output in
small sub-line chunks ;)), you'll always get unbroken reads from the
things printed into it, so the lines won't be jumbled up.

Don't rely on this combining the output of many active writers at the
same time very well though.

=head2 MULTIPLE BUCKETS

To collect from multiple buckets independently requires the use of a
I<spigot>.  A I<spigot> is considered an advanced tool used only by
experienced plumbers and is not included in this first basic set of
plumbings.

Alternatively you can probably use L<Coro> or otherwise suitably
arrange to multiprocess.  But sorry, this isn't POE.

Or, write an IO::Plumbing sub-class with an IO::Select-like interface,
that multiple objects can point themselves into, obviating the need
for any buckets.  But this interface isn't for that.

=head1 AUTHOR AND LICENCE

Copyright 2007, Sam Vilain.  All Rights Reserved.  This program is
free software; you can use it and/or modify it under the same terms as
Perl itself.

=cut

