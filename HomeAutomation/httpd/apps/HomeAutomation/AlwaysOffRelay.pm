#Copyright (c) 2014 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
#implement an on-schedule insteon on/off command

package HomeAutomation::AlwaysOffRelay;
require HomeAutomation::BaseRelay;

use strict;
our @ISA = qw(HomeAutomation::BaseRelay);

my $DEBUG = 1;

sub new {
     print STDERR "new AlwaysOffRelay\n" if $DEBUG;
     my $proto = shift;
     my $class = ref($proto) || $proto;
     my $self  = $class->SUPER::new($_[0]);
     bless $self, $class; 
     return $self;
}

sub DoSchedule {
	my $self = shift;
        my $hour = shift;
        my $min = shift;
        if ($self->{_hour} != $hour)
        {
            $self->{_hour} = $hour;
            my $dimmer = $self->{_dimmer};
            print STDERR "Setting dimmer setFast(-1)\n"  if $DEBUG;
            $dimmer->setFast(-1);        
        }
}

1;
