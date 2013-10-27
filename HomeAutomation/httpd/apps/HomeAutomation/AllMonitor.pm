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
my $MIN_EMAIL_SECONDS = 60 * 5;

our @ISA = qw(HomeAutomation::InsteonMonitor);

sub new { #argument--heartbeat timer
	my ($class) = @_;
	my $self = $class->SUPER::new($_[1], $_[2]);
	$self->{_lastEmailTime} = 0;
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
	if (!$self->_isMessageStackEmpty()) {
		my $now = time;
		if ($now - $self->{_lastEmailTime} > $MIN_EMAIL_SECONDS) {
			$self->_sendEventEmail($dimmer);
			$self->_clearMessageStack();
			$self->{_lastEmailTime} = $now;
		}
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
	# FIXME  Throttle the sendmail. 
        $self->SUPER::onEvent($dimmer, $group, $cmd1, $cmd2, $ls1, $ls2, $ls3);
	$self->_stackMessage($dimmer);
	my $now = time;
	if ($now - $self->{_lastEmailTime} > $MIN_EMAIL_SECONDS ) {
        	$self->_sendEventEmail($dimmer);
        	$self->_clearMessageStack(); 
		$self->{_lastEmailTime} = $now;
	}
}

1;
