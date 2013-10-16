#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
#This package is for originating emails or other notifications based on receipt of
#messages from insteon devices, or based on lack of receipt in a required amout
#of time.
#onTimer is to be called periodically
#onEvent is to be called when an insteon message is received.

package HomeAutomation::InsteonMonitor;
use strict;
use IPC::Open2;

my $DEBUG = 0;

sub new {
    if ($DEBUG) { print STDERR "new InsteonMonitor\n"; }
    my $proto     = shift;
    my $class     = ref($proto) || $proto;
    my $heartbeat = shift;
    my $email     = shift;
    if ( defined($heartbeat) ) {
        if ( $heartbeat > 0 ) { $heartbeat *= 60 * 60; }    #convert hrs->sec
        else { $heartbeat *= -1; }    #negative is seconds (debugging)
    }
    my $self = {};
    $self->{_heartbeat}     = $heartbeat;
    $self->{_email}         = $email;
    $self->{_notified}      = 0;
    $self->{_actual}        = 0;
    $self->{_stackedMessages} = []; #anonymous array ref
    bless( $self, $class );
    return $self;
}

sub _stackMessage {
    my $self = shift;
    my $dimmer = shift;
    my $tstr = localtime( $self->{_lastHeartbeat} );
    my $lbl  = $dimmer->name();
    my $msgStack = $self->{_stackedMessages}; 
    push (@{$msgStack},
	    "The device $lbl was activated at $tstr.");
    push (@{$msgStack},
	    "    The event was on group " . $self->{_group});
    push (@{$msgStack},
            "    And was cmd1 = " . $self->{_cmd1});
    }

sub _clearMessageStack {
    my $self = shift;
    $self->{_stackedMessages} = [];
}

sub _isMessageStackEmpty {
    my $self = shift;
    my $msgStack = $self->{_stackedMessages};
    if (!defined ($msgStack) ||
		    scalar(@$msgStack) == 0) 
	    { return 1; }
    return 0;
}

# utility function for subclasses to send an email
sub _sendEventEmail {
    my $self   = shift;
    my $dimmer = shift;
    my $lbl  = $dimmer->name();
    my $email  = $self->{_email};
    if ( defined($email) ) {
        my $stdOut;
        my $stdIn;
        my $pid  = open2( $stdOut, $stdIn, "sendmail -f diysha $email" );
        binmode $stdIn;
        print $stdIn "To: " . $email . "\r\n";
        print $stdIn "Subject: Notification regarding $lbl.\r\n";
        print $stdIn "\r\n";
	foreach my $line (@{$self->{_stackedMessages}}) {
	       	print $stdIn $line."\r\n";	}
        close $stdIn;
        my $buf;
        while ( read( $stdOut, $buf, 128 ) ) {
            print STDERR "sendmail output was: " . $buf . "\n";
        }
        waitpid( $pid, 0 );
    }
}

sub onEvent {
    my $self = shift;
    unshift @_, time;
    my $flag =  $self->recordEvent(@_);
    # append to a log file, if there is one named
    my $logFileName = $self->{_logFileName};
    if ($flag && defined($logFileName)) {
        if (open FH, ">>$logFileName") {
            print FH $self->{_fileKey} . "\t" . 
                $self->{_lastHeartbeat} . "\t" . 
		$self->{_cmd1} . "\t" . $self->{_group} . "\n";
            close FH;
        }
    }
}

sub recordEvent {
    if ($DEBUG) {
        print STDERR "recordEvent: ";
        foreach (@_) { print STDERR " arg: " . $_; }
        print STDERR "\n";
    }
    my $self = shift;
    my $time = shift;
    my $ret = 1;
    if (($self->{_lastHeartbeat} == $time) &&
	($self->{_group} == $_[1]) &&
	($self->{_cmd1} == $_[2])) { $ret = 0; }
    $self->{_lastHeartbeat} = $time;
    $self->{_notified}      = 0;
    $self->{_actual}        = 1;
    $self->{_group}         = $_[1];
    $self->{_cmd1}          = $_[2];
    return $ret;
}

sub onTimer {
    my $self = shift;
    my $ret  = 0;
    if ( !defined( $self->{_lastHeartbeat} ) ) {
        $self->{_lastHeartbeat} = time;
    }
    else {
        my $seconds = time - $self->{_lastHeartbeat};
        $ret = 1 if ( defined( $self->{_heartbeat} )
	    && ( $self->{_heartbeat} != 0 )
            && ( $seconds > $self->{_heartbeat} ) );
    }
    if ($DEBUG) {
        print STDERR "\nonTimer\n";
        foreach (@_) { print STDERR " arg: " . $_; }
        print STDERR " and ret " . $ret . "\n";
    }
    my $dimmer = shift;
    if ($ret) {
        my $email = $self->{_email};
        if ( !$self->{_notified} && defined($email) ) {

            #hartbeat expired. time to send an email
            my $stdOut;
            my $stdIn;
            my $pid  = open2( $stdOut, $stdIn, "sendmail -f diysha $email" );
            my $tstr = localtime( $self->{_lastHeartbeat} );
            my $lbl  = $dimmer->name();
            binmode $stdIn;
            print $stdIn "To: " . $email . "\r\n";
            print $stdIn "Subject: Nothing from " . $lbl
              . " in allocated time.\r\n";
            print $stdIn "\r\n";

            print $stdIn "The device $lbl has been quiet for too long.\r\n";
            if ( $self->{_actual} ) {
                print $stdIn "It was last heard from " . $tstr . ".\r\n";
                print $stdIn "The event at that time was on group "
                  . $self->{_group} . "\r\n";
                print $stdIn "And was cmd1 = " . $self->{_cmd1} . "\r\n";
            }
            else {
                print $stdIn
"The device has not raised an event since this monitor started at "
                  . $tstr . "\r\n";
            }
            close $stdIn;

  #there should not be any output from the subprocess, but log any that appears.
            my $buf;
            while ( read( $stdOut, $buf, 128 ) ) {
                print STDERR "sendmail output was: " . $buf . "\n";
            }
            waitpid( $pid, 0 );
        }
        $self->{_notified} = 1;
    }
    return $ret;
}

sub fileKey {
    my $self = shift;
    my $fk = shift;
    $self->{_fileKey} = $fk if defined($fk);
    return $self->{_fileKey};
}

sub logFileName {
    my $self = shift;
    $self->{_logFileName} = shift;
}

1;
