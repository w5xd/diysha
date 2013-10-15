#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
package HomeAutomation::InsteonMonitorMessage;
use strict;

my $DEBUG = 0;

sub new {
    if ($DEBUG) { print STDERR "new InsteonMonitor\n"; }
    my $proto     = shift;
    my $class     = ref($proto) || $proto;
    my $self = {};
    my $self->{_name} = shift;
    $self->{_actual}        = 0;
    $self->{_prevHeartbeat} = [];
    $self->{_prevGroup}     = [];
    $self->{_prevCmd1}      = [];
    bless( $self, $class );
    return $self;
}

sub onEvent {
    my $self = shift;
    my $time = shift;
    my $cmd1 = shift;
    my $group = shift;
    if ( $self->{_actual} ) {
        if ( $time - $self->{_lastHeartbeat} > 1 ) {
            push( @{$self->{_prevHeartbeat}}, $self->{_lastHeartbeat} );
            push( @{$self->{_prevGroup}},     $self->{_group} );
            push( @{$self->{_prevCmd1}},      $self->{_cmd1} );

            # limit size of prior array
            while ( @{ $self->{_prevHeartbeat} } > 9 ) {
                shift @{$self->{_prevHeartbeat}};
                shift @{$self->{_prevGroup}};
                shift @{$self->{_prevCmd1}};
            }
        }
    }
    $self->{_lastHeartbeat} = $time;
    $self->{_actual}        = 1;
    $self->{_group}         = $group;
    $self->{_cmd1}          = $cmd1;
}

sub statusMessage {
    my $self   = shift;
    my $dName  = $self->{_name};
    my $status = "The device \"" . $dName . "\"";
    if ( defined( $self->{_lastHeartbeat} ) ) {
        my $tstr = localtime( $self->{_lastHeartbeat} );
        if ( $self->{_actual} ) {
            $status .=
                " was heard from at:\n"
              . $tstr
              . " cmd1="
              . $self->{_cmd1}
              . " group="
              . $self->{_group} . "\n";
            my $i = scalar @{ $self->{_prevHeartbeat} };
            while ( $i > 0 ) {
                $i -= 1;
                $status .=
                    localtime( $self->{_prevHeartbeat}[$i] )
                  . " cmd1="
                  . $self->{_prevCmd1}[$i]
                  . " group="
                  . $self->{_prevGroup}[$i] . "\n";
            }
        }
        else {
            $status .= " has not been heard from since: " . $tstr . ".\n";
        }
        return $status;
    }
    else { return $status . " has not been monitored.\n"; }
}

1;
