#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::WaterLeakMonitor;
#The insteon Water Leak Detector device sends a heartbeat (group 4 ON)
#on some unknown interval, but about every day. And sends
#a group 1 ON when it detects a leak. 
#This class arranges for an email when the heartbeat fails to come in
#(actually, that is in the InsteonMonitor base class), and an email
#when the group 1 ON is detected, but no other messages cause an email.
use HomeAutomation::InsteonMonitor;
use strict;

my $DEBUG = 0;

our @ISA = qw(HomeAutomation::InsteonMonitor);

sub new { #argument--heartbeat timer
	my ($class) = @_;
        my $self = $class->SUPER::new(@_[1..scalar(@_)-1]);
	bless ($self, $class);
	return $self;
}

sub onTimer {
	my $self = shift;
	my $dimmer =shift;
	my $modem = shift;
        if ($self->SUPER::onTimer($dimmer, $modem))
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

        if (($group == 1) && ($cmd1 == 17)) { 
		$self->_stackMessage($dimmer);
        	$self->_sendEventEmail($dimmer);
        	$self->_clearMessageStack(); 
	}
}

1;
