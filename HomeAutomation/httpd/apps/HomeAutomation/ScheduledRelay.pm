#Copyright (c) 2014 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
#implement an on-schedule insteon on/off command

package HomeAutomation::ScheduledRelay;
require HomeAutomation::BaseRelay;
use strict;
our @ISA = qw(HomeAutomation::BaseRelay);

my $DEBUG = 0;

sub new {
    print STDERR "new ScheduledRelay\n" if $DEBUG;
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new(shift);
    my %times;
    my $nextOn = 1;
    my $a;
    while ( defined( $a = shift ) ) {
        if    ( lc (substr($a,0,2)) eq "on" )  { 
		# onNNN where NNN are the on-level
		$a = substr($a,2);
		if (length $a) { $nextOn = $a + 0 }
		else {$nextOn = 255; #no digits
	       	} }
        elsif ( lc ($a) eq "off" ) { $nextOn = 0; }
        elsif ( length($a) == 4 ) { # time in hhmm ONLY
            my $time = ( substr( $a, 0, 2 ) * 60 ) + substr( $a, 2, 2 );
            print STDERR "adding $time => $nextOn\n" if $DEBUG;
            $times{$time} = $nextOn;
        }
    }
    my @keys = sort {$a <=> $b} (keys %times);
    $self->{_times} = \%times;
    $self->{_keys} = \@keys;
    bless $self, $class;
    return $self;
}

sub DoSchedule {
    my $self  = shift;
    my $hour  = shift;
    my $min   = shift;
    my $times = $self->{_times};
    my $keys = $self->{_keys};
    my $hrs   = ( $hour * 60 ) + $min;
    my $lastLess;
    foreach my $k (@$keys) {
    	last if $k > $hrs;
	$lastLess = $k;
    }
    my $lookup = ${$times}{$lastLess};
    print STDERR "ScheduledRelay DoSchedule $hour $min v:".
    	"$lookup \"$hrs\" and \"$lastLess\"\n"  if $DEBUG;
    if ( defined($lookup) ) {
        if ( $lookup != $self->{_lastSet} ) {
            my $dimmer = $self->{_dimmer};
            print STDERR "Setting " . $dimmer->name() . " to $lookup\n"
	   	 if $DEBUG;
            $dimmer->setValue( $lookup );
            $self->{_lastSet} = $lookup;
        }
    }
}

1;
