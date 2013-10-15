#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
#specialize InsteonMonitor to send an email on receipt of any and all
#events from an insteon device, and also when its heartbeat has not
#been heard for a timeout.

package HomeAutomation::AllMonitor;
use HomeAutomation::InsteonMonitor;
use strict;

my $DEBUG = 0;

our @ISA = qw(HomeAutomation::InsteonMonitor);

sub new { #argument--heartbeat timer
	my ($class) = @_;
	my $self = $class->SUPER::new($_[1], $_[2]);
	bless ($self, $class);
	return $self;
}

sub onTimer {
	my $self = shift;
	my $dimmer =shift;
        if ($self->SUPER::onTimer($dimmer))
        {
            #heartbeat expired
	}
}

sub onEvent {
	my $self = shift;
	my $dimmer = shift;
	my $group = shift;
	my $cmd1 = shift;
	my $cmd2 = shift;
	my $ls1 = shift;
	my $ls2 = shift;
	my $ls3 = shift;
        $self->SUPER::onEvent($dimmer, $group, $cmd1, $cmd2, $ls1, $ls2, $ls3);
        $self->_sendEventEmail($dimmer);
}

1;
