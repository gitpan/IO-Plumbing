
package IO::Plumbing;

use strict;
use warnings;
use Scalar::Util qw(reftype blessed weaken refaddr);
use Carp qw(croak carp confess);

=head1 NAME

IO::Plumbing - pluggable, lazy access to system commands

=head1 SYNOPSIS

 use IO::Plumbing qw(plumb);

 my $command = IO::Plumbing->new
     ( program => "echo",
       args    => [ "Hello,",  "world" ],
     );

 # same thing
 $command = plumb("echo", args => [qw"Hello, world"]);

 $command->execute;  # starts pipeline - still running
 if ($command->ok) { # waits for completion
     # success
 }

 # input plumbing - connects FHs before running
 $command->program("cat");
 $command->args(["-e", "-n"]);
 $command->input("filename");

 if ($command->ok) {
     # no plumbing, we just caught it to a buffer
     my $output = $command->terminus->output;
 }

 # connecting pipelines
 $command->output(plumb("od", args => ["-x"]));

 # as traditional, we start from the beginning and wait
 # on the command at the end of the chain.
 $command->execute;

 if ($command->terminus->ok) {
     # success.
     print "We got:\n";
     print $command->terminus->output;
 }

 # other shorthand stuff - moral equivalents of:
 #   for reading:    zero null urandom   heredoc
 #   for writing:    null full "|gpg -e" var=`CMD`
 use IO::Plumbing qw(vent plug prng      bucket    );

 # themed import groups!
 use IO::Plumbing qw(:tools);   # everything so far

=head1 DESCRIPTION

L<IO::Plumbing> is a module designed for writing programs which work a
bit like shell scripts; where you have data sources, which are fed
into pipelines of small programs, connected to make a larger computing
machine.

The intention is that the interface behaves much like modules such as
L<IO::All>, which is capable of starting threads with external
programs.  However, the L<IO::Plumbing> object is stackable, and
relatively complex arrangements of filehandles and subprocesses are
available.

When you plug two or more of these things together, they won't start
running commands immediately - that happens the moment you try to read
from the output.  So, they are B<lazy>.

=cut

use constant COMMAND_LOST => -2;
use constant COMMAND_ERROR => -1;
use constant COMMAND_DONE => 0;
use constant COMMAND_READY => 1;
use constant COMMAND_RUNNING => 2;

sub status_name {
	my $self = shift;
	my $s = $self->status;
	($s == COMMAND_LOST    ? "lost"      :
	 $s == COMMAND_ERROR   ? "not ready" :
	 $s == COMMAND_READY   ? "ready"     :
	 $s == COMMAND_RUNNING ? "running"   :
	 $s == COMMAND_DONE    ? "completed" : "insane")
}

our $PREFER_CODE = ($^W =~ m{mswin}i);

BEGIN {
	use base qw(Exporter);
	our (@EXPORT, @EXPORT_OK, %EXPORT_TAGS, $VERSION);

	$VERSION = "0.05";

	our @handyman = qw(plumb prng  plug  bucket vent hose );

	our @extra = qw(spigot alarm);
	%EXPORT_TAGS =
		(
		constants => [qw(COMMAND_ERROR COMMAND_READY COMMAND_RUNNING
			COMMAND_DONE COMMAND_LOST)],
		tools => \@handyman,
		);
	@EXPORT_OK = (map { @$_ } values %EXPORT_TAGS);

	# enable debugging with an environment variable to allow it to
	# be optimised away when it's off
	if ($ENV{IO_PLUMBING_DEBUG}) {
		*DEBUG = sub() { $ENV{IO_PLUMBING_DEBUG} }
	}
	else {
		*DEBUG = sub() { }
	}
}

# no Moose; this needs to be quite tight
sub new {
	my $class = shift;
	my $self = bless {}, $class;
	while ( my ($prop, $value) = splice @_, 0, 2 ) {
		if ( !$self->can($prop) ) {
			confess "bad \@_!  $prop => $value";
		}
		$self->$prop($value);
	}
	$self->BUILDALL;
	$self;
}

# just for fun
sub BUILDALL {
	my $self = shift;

	my @c3 = (sort { $a->isa($b) <=> $b->isa($a) }
		(do {
			my (@x, %x);
			while (my $c = shift @x ) {
				no strict 'refs';
				push @x,grep{!$x{$c}++}
				    @{"${c}::ISA"}
			}
			keys %x
		}));

	for my $c ( @c3 ) {
		if ( defined &{"${c}::BUILD"} ) {
			&{"${c}::BUILD"}($self);
		}
	}
}

=head1 FUNCTIONS

=head2 THE BASIC PLUMBINGS

These functions all return a new L<IO::Plumbing> object with a
different configuration.

=over

=item plumb(cmdline, arg => value, ...)

Shortcut for making a new IO::Plumbing object.  Passing in a
C<cmdline> with a space indicates that you want shell de-quoting.

=cut

sub plumb {
	my $cmdline = shift;
	my @args;
	if ( ref $cmdline eq "CODE" ) {
		push @args, code => $cmdline;
	}
	elsif ( ref $cmdline eq "ARRAY" or !ref $cmdline ) {
		push @args, cmdline => $cmdline;
	}
	elsif ( ref $cmdline eq "HASH" and !@_ ) {
		@args = %$cmdline;
	}
	elsif ( !ref $cmdline ) {
		warn "what?  $cmdline\n";
		@args = ($cmdline, @_);
	}
	else {
		croak "invalid argument to plumb; $cmdline";
	}
	__PACKAGE__->new( @args, @_ );
}

=item prng()

Shortcut for C</dev/urandom> or other such locally available source of
relatively entropic bit sequences.

When written to, creates a L<gpg> instance that encrypts to the
default recipient.

=cut

sub prng {
	IO::Plumbing::PRNG->new(@_);
}

=item plug()

When read from, always returns end of file, like F</dev/null> on Unix.

When written to, always returns an error, like F</dev/full> on Unix.
This is slightly different to the filehandle being closed.  To use a
real closed filehandle, just pass one in to B<input()>, B<output()> or
B<stderr()>.

=cut

sub plug {
	IO::Plumbing::Plug->new(@_);
}

=item bucket( [ $contents ] )

A small (= in-core) spool of data.  Returns end of file when the data
has been sent.  Specifying the contents is enough to do this.

When written to, fills with data as the process writes.  In that case,
the contents will normally be a pointer to an array or scalar to fill
with input records.

Now, the thing about all of this is that you can only be pouring into
one bucket at a time as the parent process is responsible for this.
So, remember to only use one bucket at a time until that's all sorted
out.

=cut

sub bucket {
	if ( defined $_[0] ) {
		IO::Plumbing::Bucket->new(contents => \$_[0], @_[1..$#_]);
	} else {
		IO::Plumbing::Bucket->new(@_[1..$#_]);
	}
}

=item vent( [ $generator ] )

When read from, returns a stream of zeros (by default - or supply
C<$generator>), like F</dev/zero> on Unix.

When written to, happily consumes any amount of data without returning
an error, like F</dev/null> on Unix.

=cut

sub vent {
    my $generator = shift;
    if ( $generator and !ref $generator ) {
	my $text = $generator;
	$generator = sub { 1 while print $text; };
    }
    if ( $generator ) {
	plumb(undef, code => $generator, @_);
    } else {
	IO::Plumbing::Vent->new(@_);
    }
}

=item hose( [ ... ] )

This represents a filehandle.  This class is responsible for plugging
into an IO::Plumbing contraption, and giving you a filehandle that you
can read from or write to.

Arguments are passed to IO::Plumbing::Hose->new();

=cut

sub hose {
	IO::Plumbing::Hose->new(@_);
}

=back

=head1 METHODS

Many of these methods are object properties.

=cut

sub status {
	if ( !defined($_[0]->{status}) ) {
		$_[0]->{status} = COMMAND_ERROR;
	}
	return $_[0]->{status};
}

=over

=cut

=item cwd( $path )

Specify a directory to change to after C<fork()> time.  Honoured for
code reference blocks, too.  Defaults to C<undef>, which does not
alter the working directory.

=cut

sub cwd { $_[0]->{cwd} = $_[1] if @_>1; $_[0]->{cwd} }

=item env( [ { KEY => VALUE, ... } ])

Specify the process environment to use in the child.  Defaults to
C<undef>, which does not alter the environment.

=cut

sub env { $_[0]->{env} = $_[1] if @_>1; $_[0]->{env} }

=item program( [ $path ] )

Specify the program to execute.

=cut

sub program {
	my $self = shift;
	if ( @_ ) {
		my $prog = shift;
		$self->{program} = $prog;

		my $old_st = $self->{status};
		$self->{status} = COMMAND_READY
		    if ($self->status == COMMAND_ERROR and $prog);
		$self->{status} = COMMAND_ERROR
		    if ($self->status == COMMAND_READY and !$prog);
	}
	$self->{program};
};

=item args( [ @command ] )

Specify a list of arguments to the command.  ie, what gets passed to
@ARGV in the child.  Can be a list of strings or an ArrayRef.

=cut

sub args {
	my $self = shift;
	if ( @_ ) {
		if ( ref $_[0] && reftype $_[0] eq "ARRAY" ) {
			$self->{args} = $_[0];
		}
		elsif ( !ref $_[0] ) {
			$self->{args} = [@_];
		}
		else {
			croak "bad plumbing args: @_";
		}
	}
	$self->{args};
}

=item all_args()

primarily of interest to those sub-classing the module, this lets you
return something other than what "args" was set to when it comes time
to execute.

=cut

sub all_args {
	my $self = shift;
	if ( $self->{args} ) {
		return @{ $self->args };
	}
	else {
		return();
	}
}

=item cmdline("xxx")

As a shortcut to specifying program and args, specify a command line.
No shell redirection is yet supported, only basic de-quoting.

=cut

sub cmdline {
	my $self = shift;

	unless (defined &shell_unquote) {
		require IO::Plumbing::Util;
		IO::Plumbing::Util->import("shell_quote", "shell_unquote");
 	}

	if ( @_ == 1 and $_[0] and $_[0] =~ m{\s} ) {
		@_ = &shell_unquote($_[0]);
	}

	if ( @_ ) {
		$self->program(shift);
		$self->args(@_);
	}

	if ( $self->program ) {
		if ( wantarray ) {
			return ($self->program, @{ $self->args||[] });
		}
		elsif ( defined wantarray ) {
			return &shell_quote($self->program, @{ $self->args||[] });
		}
	}
	else {
		return "(code block)";
	}
}

=item code( sub { ... } )

Specify a piece of code to run, instead of executing a program.  when
the block is finished the child process will call exit(0).

If both code and an external program are passed, then the code block
will be run.  It receives the L<IO::Plumbing> object as its first
argument and the command line arguments after that.

=cut

sub code {
	my $self = shift;
	if ( @_ == 1 ) {
		$self->{code} = shift;
		if ( defined $self->{code} ) {
			$self->{status} = COMMAND_READY;
		}
	}
	$self->{code};
}

=item input( [ $source] [, $weakref ] )

Specify the input source of this command pipe.  Defaults to a plug.

If you pass a filehandle in, you might also like to call
C<-E<gt>close_on_exec($source)> on it to mark it to close when the
pipeline executes.

If you pass in another B<IO::Plumbing> object (or something which
quacks like one), then that object's C<output> property is
automatically set to point back at this object.  So, an
C<IO::Plumbing> chain is a doubly-linked list.  The C<$weakref> flag
indicates this is what is happening, and aims to stop these circular
references, which might otherwise cause memory leaks.

=cut

use IO::File;

sub _parse_direction {
	( $_[0]
	  ? ( $_[0] eq "input" ? $_[0] : "output" )
	  : "input" );
}

sub _not_direction {
	( $_[0]
	  ? ( $_[0] eq "input" ? "output" : "input" )
	  : "output" );
}

sub get_plumb {
	my $self = shift;
	my $direction = _parse_direction(shift);
	my $number = (shift) || 0;

	$self->{$direction}[$number][0];
}

sub get_plumb_pair {
	my $self = shift;
	my $direction = _parse_direction(shift);
	my $number = (shift) || 0;

	$self->{$direction}[$number][1];
}

sub has_plumb {
	my $self = shift;
	!!$self->get_plumb(@_);
}

sub connect_plumb {
	my $self = shift;
	my $direction = _parse_direction(shift);
	my $number = (shift) || 0;

	my $plumb = shift;
	my $reverse = (shift);
	my $weak = shift;

	$self->{$direction}[$number] = [ $plumb, $reverse ];

	if ( $weak ) {
		weaken($self->{$direction}[$number][0]);
		$self->connect_hook($direction, $number);
	}
	else {
		if ( blessed $plumb and $plumb->can("connect_plumb") ) {
			$plumb->connect_plumb
				( _not_direction($direction), $reverse,
				  $self, $number, 1
				);
			$self->connect_hook($direction, $number);
		}
	}
}

sub connect_hook { }

sub default_input {
	my $self = shift;
	plug;
}

=item output( [ $dest] [, $weakref ] )

Specify the output this command pipe.  Defaults to a bucket.

Pass in "|cmdname" as a string for a quick way to make more plumbing.

=item stderr( [ $dest] [, $weakref ] )

Specify where stderr of this stage goes.  Defaults to C<STDERR> of the
current process.

=item connect_plumb( $direction, $number, $plumb, $reverse, $weak )

This is a generic interface to connect any plumb to any slot of the
plumbing.  The above three methods are shortcuts to invokation of this
method.

C<$direction> can be C<undef>, 0 or "input" to mean input, anything
else means output.

The C<$reverse> parameter refers to which plumbing slot to plumb the
other way into.  C<undef> or 0 means the first slot, which also
conveniently generally does what you wanted.

C<$weak> means to make the reference to C<$plumb> a "weak" reference,
and to not try to make a corresponding counter-plumb.  This is used to
break the infinite loop that might otherwise eventuate and would not
normally be passed in by a user of this module.

This example:

  $plumb->connect_plumb( input => 0, $plumb2, 1 );

Connects the standard error of C<$plumb2> to the standard input of
C<$plumb>.

=item has_plumb( $direction, $number )

=item get_plumb( $direction, $number )

Predicate/accessors for the plumbs at the various slots.  Same input
as the above.

=item get_plumb_pair( $direction, $number )

=cut

my $looking_for = <<THESE; # ??
sub input {
sub output {
sub stderr {
THESE

BEGIN {
	my @fhs =
		([ "input",  0, 0, 0, "in"  ],
		 [ "output", 1, 0, 1, "out" ],
		 [ "stderr", 1, 1, 2, "err" ]);

	for my $i ( @fhs ) {
		no strict 'refs';
		my ($name, $direction, $number, $fd_num, $fd_name) = @$i;
		my $default_func = "default_$name";
		my $pat = $direction ? qr{\A\s*|(.*)\Z}
			: qr{(.*)\|\s*\Z}s;

		*$name = sub {
			my $self = shift;
			if ( @_ or ! $self->has_plumb($direction, $number) ) {
				if ( $self->has_plumb($direction, $number) &&
				     $_[0] &&
				     $_[0] == $self->get_plumb
				     ($direction, $number) ) {
					return;
				}

				my $plumb = (shift) || $self->$default_func;
				my $reverse = (shift) || 0;

				if ( defined $plumb and !ref $plumb ) {
					if ( $plumb =~ m{$pat} ) {
						$plumb = plumb($1);
					}
				}
				elsif ( $plumb and ref $plumb eq "CODE" ) {
					$plumb = plumb(undef, code => $plumb);
				}

				$self->connect_plumb
					($direction => $number,
					 $plumb, $reverse);
			}
			$self->get_plumb($direction => $number);
		};

		my $fd_func = "${fd_name}_fh";
		*$fd_func = sub {
			my $self = shift;
			if ( @_ ) {
				$self->set_fd( $fd_num, @_ );
			}
			elsif ( !$self->has_fd( $fd_num ) ) {
				$self->_open
					($name, $fd_func,
					 $direction, $number);
			}
			$self->get_fd( $fd_num );
		};
	}
}

sub default_stderr { \*STDERR }
sub default_output { bucket }

our %running;

=item terminus()

Returns the last output object on the "output" chain of this pipeline.
Frequently a bucket.

=cut

sub terminus {
	my $self = shift;
	my $output = $self->output;
	my $last_output = $self;
	while ( UNIVERSAL::isa($output, __PACKAGE__) ) {
		$last_output = $output;
		$output = $output->output;
	}
	return $last_output;
}

=item status()

Returns the current status of this piece of plumbing;

  Value             Meaning
  --------------------------------------------------
  COMMAND_ERROR     Not good enough to exec() yet
  COMMAND_READY     Got everything we need to run
  COMMAND_RUNNING   In progress
  COMMAND_DONE      Reaped
  COMMAND_LOST      Process went AWOL

=item ready()

=item running()

=item done()

Aliases for checking whether the status is one of them

=item status_name()

Returns a description of the current status of the process

=cut

sub ready   { $_[0]->status == COMMAND_READY   }
sub running { $_[0]->status == COMMAND_RUNNING }
sub done    { $_[0]->status == COMMAND_DONE    }

=item pid()

Returns the process ID of the running (or completed) process.

=cut

sub pid { $_[0]->{pid} = $_[1] if @_>1; $_[0]->{pid} }

sub BUILD {
	my $self = shift;
	if ( $self->program and $self->status == COMMAND_ERROR ) {
		$self->{status} = COMMAND_READY;
	}
}

=item rc()

Returns the current return code of the process (ie, what C<$?> was set
to).  If undefined, the program hasn't finished (or isn't started yet);

=cut

sub rc {
	my $self = shift;
	if ( @_ ) {
		$self->{rc} = shift;
		warn "$self: RC = $self->{rc}\n"
			if DEBUG && DEBUG ge "1";
		if ( defined $self->{rc} ) {
			$self->{status} = COMMAND_DONE;
		}
	}
	$self->{rc};
}

=item ok()

Returns true if the program exited cleanly.

=cut

sub ok {
	my $self = shift;
	if ( !$self->done ) {
		$self->execute if $self->ready;
		$self->wait    if $self->running;
	}
	return undef   if not $self->done;
	return ($self->rc == 0);
}

=item error()

Returns a true value if the process returned an error code.  Includes
in the message whether the program exited cleanly, exited with an
error code (and if so what the error code was), as well as whether it
was killed by a signal (and what the signal was).

=cut

sub error {
	my $self = shift;
	if ( !$self->done ) {
		$self->execute if $self->ready;
		$self->wait    if $self->running;
	}
	die "$self: didn't run" if not $self->done;

	my $message;
	if ( $self->rc == 0 ) {
		$message = undef;
	}
	elsif ( $self->rc & 255 ) {
		$message = "killed by signal ".$self->rc
	}
	else {
		my $exit_code = $self->rc >> 8;
		$message = "exited with error code ".$exit_code;
	}

	$message;
}

=item errormsg()

Just like error, except guaranteed to never produce a "use of
uninitialised variable" warning by returning "finished normally" if
the process ran successfully.

=cut

sub errormsg { $_[0]->error || "finished normally" }

=item wait()

Waits for this specific piece of plumbing to finish.

=cut

sub wait {
	my $self = shift;
	my $pid = $self->pid
		or croak "wait on process in state ".$self->status_name;

	warn "$self: waiting on pid $pid\n"
		if DEBUG && DEBUG ge "1";

	my $found = waitpid($pid, 0);
	my $rc = $?;
	if ( $found == $pid ) {
		$self->rc($rc);
	}
	else {
		warn "$self: ignoring RC from pid $pid";
		$self->{status} = COMMAND_LOST;
	}

	return $self->rc;
}

=item name

Returns (or sets) a string descriptor for this piece of plumbing.

Available as the overloaded '""' (stringify) operator.

=cut

sub name {
	my $self = shift;
	my $type = lc ref $self;
	$type =~ s{io::plumbing::}{};
	$type = "plumb" if $type eq lc __PACKAGE__;
	if ( $self->{program} ) {
		$type.="(".$self->cmdline.")";
	}
	elsif ( $self->{code} ) {
		$type.="(".$self->{code}.")";
	}
	if ( $self->needs_fork ) {
		$type.="[".($self->pid||"tbc")."]";
	}
	$type;
}

sub _equal {
	my $self = shift;
	my $other = shift;
	return ( ref $other and refaddr $self == refaddr $other );
}

use overload
	'""' => sub{ $_[0]->name },
	'==' => sub{ $_[0]->_equal($_[1]) },
	fallback => 1;

sub fd_num {
	my $self = shift;
	my $direction = _parse_direction(shift);
	my $number = (shift) || 0;
	$self->fd_shape->{$direction}[$number];
}

sub fd_shape {
	({ input => [ 0 ],
	   output => [ 1, 2 ] });
}

sub get_fd {
	my $self = shift;
	my $number = (shift) || 0;
	$self->{fd}[$number]
}

sub has_fd {
	my $self = shift;
	!!$self->get_fd(@_);
}

sub set_fd {
	my $self = shift;
	my $number = (shift) || 0;
	my $fd = shift;
	my $close_on_exec = shift;

	$self->{fd}[$number] = $fd;
	if ( $close_on_exec ) {
		$self->close_on_exec($fd);
	}

	warn "$self: FD $number = FH#".fileno($fd)
		."; close_on_exec = ".($close_on_exec?"on":"off")."\n"
			if DEBUG && DEBUG ge "1";
}

=item out_fh( [ $fh ] [ , $close_on_exec ] )

specify (or return) the filehandle that will become this child
process' STDOUT

=item err_fh( [ $fh ] )

specify (or return) the filehandle that will become this child
process' STDERR

=item has_fd( $num )

=item get_fd( $num )

=item set_fd( $num, $fd, [$close_on_exec] )

This is a generic interface to the various *_fh functions.  Instead of
specifying the filehandle you want to get or set by the name of the
method, use the filehandle identifier.  When the plumb is executed,
filehandles will be connected appropriately.

=cut

sub _open {
	my $self = shift;
	my $which = shift;
	my $what = $self->$which;
	my $method = shift;
	my $direction = shift;
	my $number = shift;

	if ( DEBUG and DEBUG ge "3" ) {
		warn "$self: opening $which - what is '$what'";
	}

	if (!ref($what)) {
		if ( !defined $what or !length $what ) {
			confess "Something tried to open nothing for $which";
		}
		my $dir = ($direction ? "writing" : "reading");
		my $io = new IO::File;
		$io->open($what, ($direction ? ">" : "<") )
			or die "failed to open $which file $what for "
				.$dir."; $!";
		warn "$self: opened '$what' for $dir on FH#"
			.fileno($io)."\n" if DEBUG;

		# set close-on-exec: no need for parent to hold open
		$self->$method($io, 1);
	}
	elsif ( ref $what eq "GLOB" or
		( blessed $what and
		  $what->isa("IO::Handle") ) ) {

		# don't set close-on-exec: FIXME: why?
		$self->$method($what);
	}
	elsif ( blessed($what) ) {

		# figure out which FH on the other this one is tied to
		my $o = $self->get_plumb_pair($direction, $number);

		if ( ! $what->needs_pipe( !$direction, $o ) ) {

			# no pipe needed? well, give us a FH then.
			my $fh = $what->get_fd_pair(!$direction, $o);
			$self->$method($fh, $self->needs_fork);

		}
		elsif ( $what->can("set_fd") ) {

			my ($in, $out);
			pipe $in, $out;
			warn "$self: made pipe ".fileno($out)." -> ".
				fileno($in)."\n" if DEBUG;

			my ($mine, $theirs) =
				($direction
				 ? ($out, $in)
				 : ($in, $out));

			$self->$method($mine, $self->needs_fork);
			my $nd = _not_direction($direction);
			my $fd_num = $what->fd_num($nd, $o);
			$what->set_fd
				( $fd_num, $theirs, $what->needs_fork );
		}
		else {
			confess "_open() called with what = $what";
		}
	}
}

=item in_fh( [ $fh ] [ , $close_on_exec ] )

specify (or return) the filehandle that will become this child
process' STDIN.

=item execute()

starts this pipeline.  Any link can be the starting point for an execute()

=cut

sub execute {
	my $self = shift;

	warn "$self->execute\n" if DEBUG;

	return undef if $self->running or $self->done;

	# input starts first, so if we were executed first we hand
	# control back up.
	my $input = $self->input;
	if ( blessed $input and $input->isa(__PACKAGE__) ) {
		warn "$self->execute chaining in $input->execute\n" if DEBUG;
		return $input->execute unless $input->running;
	}

	unless ( !$self->needs_fork or $self->program or $self->code ) {
		croak "execute without program";
	}

	# setup plumbing first
	my @args = ($self->program, $self->all_args);
	if ( $self->code and (!$self->cmdline or $self->prefer_code) ) {
		$args[0] = $self;
	}

	my ($child_stdin, $child_stdout, $child_stderr);

	if ( $self->needs_fork ) {
		# collect the filehandles before forking; some of them might
		# require pipes to be made.
		warn "$self about to open input\n" if DEBUG and DEBUG gt "2";
		$child_stdin = $self->in_fh;
		warn "$self about to open output\n" if DEBUG and DEBUG gt "2";
		$child_stdout = $self->out_fh;
		warn "$self about to open error\n" if DEBUG and DEBUG gt "2";
		$child_stderr = $self->err_fh;
		warn "$self set FDs: ("
			.(join ",", map{ $_ ? fileno($_) : "-" }
			  $child_stdin, $child_stdout, $child_stderr)
				.")\n" if DEBUG;
	}

	# for extensions - to do any extra plumbing they want
	$self->pre_fork_hook if $self->can("pre_fork_hook");

	my $pid;
	if ($self->needs_fork) {
		$pid = $self->do_fork();
		if ( $pid ) {
			# close all the child filehandles
			my $coe = delete $self->{close_on_exec};
			for my $fh ( @$coe ) {
				warn "$self: closing FD ".fileno($fh)."\n"
					if DEBUG and $fh;
				close($fh);
			}
		}

		$running{$pid} = $self;
		$self->{pid} = $pid;
	}

	if ( !$self->needs_fork or $pid ) {

		$self->{status} = COMMAND_RUNNING;

		# finally, continue the execution down the pipeline
		my $output = $self->output;
		if ( blessed $output and $output->isa(__PACKAGE__) ) {
			warn "$self chaining out $output->execute\n"
				if DEBUG;
			$output->execute;
		}
		else {
			warn "$self not chaining out ".($output||"nothing")."\n"
				if DEBUG;
		}

	}
	else {

		# child process - connect the new filehandles with our
		# basic handles.
		$self->_setup_fd(\*STDIN, "<", $child_stdin, "stdin");
		$self->_setup_fd(\*STDOUT, ">", $child_stdout, "stdout");
		$self->_setup_fd(\*STDERR, ">", $child_stderr, "stderr");
		# another extensions hook
		$self->pre_exec_hook if $self->can("pre_exec_hook");

		chdir($self->cwd) if defined $self->cwd;
		# more general plumbing TO-DO - see also
		# Scriptalicious::setup_fds
		###$self->debug_print("child pid $$ exec(".shell_quote(@args).")");

		if ( $self->code ) {
			$self->code->(@args);
			exit(0);
		}
		else {
			exec @args;
		}
		die "exec() returned";
	}

	# as is tradition
	return $pid;
}

sub do_fork {
	my $self = shift;
	my $pid = fork();
	die "fork() failed; $!" unless defined $pid;
	$self->{pid} = $pid || $$;
	warn "$self->fork ($$ begat $pid)\n" if DEBUG and $pid;
	return $pid;
}

sub needs_fork {
	1;
}

sub needs_pipe {
	my $self = shift;
	$self->needs_fork;
}

sub _fileno {
	my $ent = shift;
	if ( ref($ent) ) {
		if ( reftype($ent) eq "GLOB" ) {
			return fileno($ent);
		}
		else {
			return "?";
		}
	} else {
		return "-";
	}
}

sub _setup_fd {
	my $self = shift;
	my $glob = shift;
	my $mode = shift;
	my $fh = shift;
	my $name = shift;
	if ( !$fh ) {
		close($glob);
	}
	else {
		my $fn;
		eval { $fn = fileno($fh) };
		die "didn't get a fileno from $fh for $name; $@\n"
			unless defined $fn;
		# 'Filehandle STDIN reopened as STDOUT only for output'.
		# I think that warning is wrong.
		warn "$self: FH ".fileno($glob)." to FH $fn\n"
			if DEBUG;
		no warnings;
		open $glob, $mode."&=$fn";
	}
}


=item close_on_exec($fh [, $fh, ...])

Mark a filehandle that should be closed I<in the parent process> when
the pipeline is executed.  Note that this is quite a different concept
to the OS-level I<close on exec>, which is hinted about at
L<perlvar/$^F>, which applies to filehandles which are closed I<in the
child process>.  B<IO::Plumbing> does not alter C<$^F>.

If you are passing raw filehandles in, the module can't guess whether
this filehandle is one that should be closed on execution of the
pipeline, or whether it's one that as a parent process you intend to
feed or read yourself.

With a normal file, that's not a huge problem - just a wasted FD in
the parent process.  With the input half of a pipe, it means that the
other end will not see the filehandle closed when a sub-process closes
it, and hence your pipeline will block as the next program waits
forever for an end of file.

So long as you always pass B<IO::Plumbing> objects to the C<input> and
C<output> methods, you don't need to use this function; when those are
converted from objects to filehandles, the temporary filehandles are
always marked close on exec.

=cut

sub close_on_exec {
	my $self = shift;
	while ( my $fh = shift ) {
		die "rubbish passed to close_on_exec: $fh"
			unless reftype($fh) eq "GLOB";
		push @{$self->{close_on_exec}||=[]}, $fh;
	}
}

=back

=head1 CLASS METHODS

These may also be called as object methods

=over

=item IO::Plumbing->new( $att => $value, [ ... ] )

The constructor is very basic, it just calls bare accessors based on
C<$att> and C<$value> and then calls C<BUILD>.

=item IO::Plumbing->reap( [ $max ] )

check for any waiting children and update the RC values of all running
plumbing objects, without ever blocking.

C<$max> specifies the maximum number of children to reap at one time.

=cut

use POSIX qw( :sys_wait_h );

sub _reap_one {
	my $pid = waitpid(-1, WNOHANG);
	return undef if ($pid||-1) <= 0;
	my $cp = delete $running{$pid};
	if ( $cp ) {
		$cp->rc($?);
	}
	else {
		warn __PACKAGE__."::_reap_one reaped unknown child "
			."PID = $pid\n";
	}
	return 1;
}

sub reap {
	if ( $_[1] ) {
		for ( 1..$_[1] ) {
			_reap_one() or last;
		}
	}
	else {
		1 while _reap_one;
	}
	if ( ref $_[0] ) {
		return $_[0]->done;
	}
}

sub prefer_code {
	my $self = shift;
	return $PREFER_CODE;
}

=back

=cut

use Class::Autouse map { __PACKAGE__."::".$_ }
	qw(Plug PRNG Vent Bucket Hose);

1;

__END__

=head1 SUB-CLASS API

=head2 OVERRIDABLE METHODS

=over

=item default_input

What to use as a default standard input when nothing else is given.
Defaults to a L<IO::Plumbing::Plug> (C</dev/null>).  Override this in
a sub-class to change this behaviour.

=item default_output

What to use as a default standard output.  Defaults to a
L<IO::Plumbing::Bucket> (ie, a variable buffer).

=item default_stderr

Default standard error.  Defaults to the calling process' C<STDERR>.

=item needs_fork

Set this to return a true value if this piece of plumbing needs to
fork; false otherwise.

=item needs_pipe( $direction, $number )

This is called when a plumb is about to set up FDs to another one.

=item fd_shape

This method should return a hash of arrays; it represents which input
or output filehandle is connected to which system FD number.  The
default is:

  { input => [ 0 ], output => [ 1, 2 ] }

=item fd_num ( $direction, $number )

Functional interface to the above - return the (post-plumbed) FD
number of the given output/slot pair.  These arguments are the same as
to L</connect_plumb>;

=item do_fork

A hook for forking

=item connect_hook ( $direction, $number )

A hook that is called once a connection is made.

=item prefer_code

This is another way to specify the code vs program behaviour of the
plumbing; it is used by the default execute() function to decide
whether to invoke an external program, or use the supplied code block,
if both are provided.

The default is to prefer code on Windows.

=back

=head1 DEBUGGING

To get debug information to STDERR about forking and plumbing, set
C<IO_PLUMBING_DEBUG> in the environment to 1.

To get further information useful for debugging the IO::Plumbing
module, set it to 2 or higher.

=head1 AUTHOR AND LICENCE

Copyright 2007, 2008, Sam Vilain.  All Rights Reserved.  This program
is free software; you can use it and/or modify it under the same terms
as Perl itself.

=head1 BUGS / SUBMISSIONS

This is still currently quite experimental code, so it's quite likely
that something straightforward you expect to work doesn't.

In particular, currently this module has not been ported to run under
Windows; please e-mail the author if you are interested in adding
support for that.

If you find an error, please submit the failure as an addition to the
test suite, as a patch.  Version control is at:

 git://utsl.gen.nz/IO-Plumbing

See the file F<SubmittingPatches> in the distribution for a basic
command sequence you can use for this.  Feel free to also harass me
via L<https://rt.cpan.org/Ticket/Create.html?Queue=IO%3A%3APlumbing>
or mail me something other than a patch, but you win points for just
submitting a patch in `git-format-patch` format that I can easily
apply and work on next time.

To take that to its logical extension, you can expect well written
patch series which include test cases and clearly described
progressive changes to spur me to release a new version of the module
with your great new feature in it.  Because I hopefully didn't have to
do any coding for that, just review.

=cut

