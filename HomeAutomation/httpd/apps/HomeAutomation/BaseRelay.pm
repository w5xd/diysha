#Copyright (c) 2014 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
# helper base class for the relay scheduling to make the scheduler
# have enough Dimmer methods on it to look like a dimmer.

package HomeAutomation::BaseRelay;
use strict;

my $DEBUG = 0;

sub new {
     print STDERR "new BaseRelay\n" if $DEBUG;
     my $class = shift;
     my $dimmer  = shift;
     my $self = {};
     my $self->{_dimmer} = $dimmer;
     bless $self, $class; 
     return $self;
}

sub startGatherLinkTable {
     my $self = shift;
     my $dimmer = $self->{_dimmer};
     return $dimmer->startGatherLinkTable();
}

sub getNumberOfLinks {
    my $self = shift;
    my $dimmer = $self->{_dimmer};
    return $dimmer->getNumberOfLinks();
}

sub name {
    my $self = shift;
    my $dimmer = $self->{_dimmer};
    return $dimmer->name();
}

sub printLinkTable {
    my $self = shift;
    my $dimmer = $self->{_dimmer};
    return $dimmer->printLinkTable();
}

1;
