#line 1

package Test::Depends;

use strict 'vars', 'subs';
use 5.006;
use warnings;

our $VERSION = 0.06;

#line 24

use Data::Dumper;

sub import {
    my $package = shift;
    my $caller = caller();

    my @missing;

    while ( my $package = shift ) {
	my $eval = ("# line 0 \"Test::Depends generated\"\n"
		    ."package $caller;\n");
	my $import = "";
	my $wanted_version;
	if ( ref $package and ref $package eq "ARRAY" ) {
	    ($package, my @args) = (@$package);
	    no warnings 'numeric';
	    if ( @args == 1 and
		 not ref $args[0] and
		 ( $args[0]+0 != 0 or $args[0]+0 eq $args[0] )
	       ) {
		$wanted_version = $args[0];
		($import = $wanted_version) =~ s{'}{\'}g;
		$import = " '$import'";
	    } else {
		local($Data::Dumper::Purity) = 1;
		local($Data::Dumper::Varname) = "bob";
		my $dumped = Data::Dumper->Dump([\@args]);
		$dumped =~ s{\A\$bob1 = }{};
		$import = ' @{'.$dumped.'}';
	    }
	}
	$eval .= "use $package$import;";
	eval $eval;
	$eval =~ s{^}{#    }mg;
	#print STDERR "# RAN:\n$eval\n" if ( -t STDOUT );
	if ( $@ ) {
	    (my $pm = $package) =~ s{::}{/}g;
	    $pm .= ".pm";
	    if ( $wanted_version and ${"${package}::VERSION"} ) {
		push @missing, "$package (${$package.'::VERSION'} < $wanted_version)", $@;
	    } elsif ( exists $INC{$pm} ) {
		push @missing, "$package (import failure)", $@;
	    } else {
		push @missing, "$package", $@;
	    }
	}
    }

    if ( @missing ) {
	print("1..0 # Skip missing/broken dependancies");
	if ( -t STDOUT ) {
	    print "\n";
	    while ( my ($pkg, $err) = splice @missing, 0, 2 ) {
		$err =~ s{^}{\t}gm;
		print STDERR ("ERROR - pre-requisite $pkg "
			      ."failed to load:\n$err\n");
	    }
	} else {
	    my $i;
	    print "; ".join(", ", grep { !($i++ % 2) } @missing)."\n";
	}
	exit(0);
    }

}

1;

__END__

#line 135

