# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::EventCheckEheat;

use strict;
require Math::Round;

sub new {
    my $class = shift;
    my $self  = {
        _vars    => shift,
        _records => {},     # to test: { TODELETE => [ time - 3590, "25.3" ], },
    };
    my $minTemp = $self->{_vars}->{HEATPUMP_MIN_TEMPERATURE_F};
    $minTemp = Math::Round::nearest( 1, $minTemp );
    if ( $minTemp < 0 ) {
        print STDERR
          "rejecting HEATPUMP_MIN_TEMPERATURE_F $minTemp and setting to 0\n";
        $minTemp = 0;
    }
    if ( $minTemp > 50 ) {
        print STDERR
          "rejecting HEATPUMP_MIN_TEMPERATURE_F $minTemp and setting to 50\n";
        $minTemp = 50;
    }
    print STDERR "HEATPUMP_MIN_TEMPERATURE $minTemp\n";
    $self->{_minTemp} = $minTemp;
    bless $self, $class;
    return $self;
}

sub temperatureEvent {
    my $self         = shift;
    my $temperatureF = shift;
    my $source       = shift;
    my $minTemp      = $self->{_minTemp};
    my $records      = $self->{_records};
    if ( $temperatureF > 150 ) {
        print STDERR "discarding temperature $temperatureF from $source\n";
        return 1;
    }
    elsif ( $temperatureF < -60 ) {
        printf STDERR "discarding temperature $temperatureF from $source\n";
        return 1;
    }
    my @record = ( time, $temperatureF );    #time stamped observation
    $records->{$source} = \@record;

    #go through
    my $valid = 0;
    my $now   = time;
    my $max   = -9999;
    my $min   = 9999;
    while ( my ( $key, $val ) = each(%$records) ) {
        my $age = $now - $val->[0];
        if ( $age > 3600 ) {
            print STDERR "discarding $key at age $age\n";
            delete $records->{$key};
        }
        else {
            my $t = $val->[1];
            $t = Math::Round::nearest( 1, $t );
            if ( $t > $max ) { $max = $t; }
            if ( $t < $min ) { $min = $t; }
        }
    }

    my $cmd;
    my $FURNACE_LOGIN = $self->{_vars}->{FURNACE_LOGIN};
    if ( !defined($FURNACE_LOGIN) || $FURNACE_LOGIN eq "" )
    {    #use WirelessGateway to talk to Packet Thermostat
        my $cmdBase =
            $ENV{HTTPD_LOCAL_ROOT}
          . "/../hvac/procWirelessGateway "
          . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
          . " SEND "
          . $self->{_vars}->{FURNACE_NODEID}
          . " HVAC TYPE=";
        if ( $min < $minTemp ) {
            $cmd = $cmdBase . "1 MODE=0";    # set to NoHP
        }
        elsif ( $min > $minTemp ) {
            $cmd = $cmdBase . "0 MODE=0";    # set to PasT
        }
    }
    else {                                   #use curl to talk to modtronix
        my $FURNACE_IP = $self->{_vars}->{FURNACE_IP};
        if ( $min < $minTemp ) {
            $cmd =
"curl --max-time 30 --silent $FURNACE_LOGIN http://$FURNACE_IP/nothing?xr5=1 > /dev/null 2>&1";
        }

        #note that $min == $minTemp is NOT processed
        elsif ( $min > $minTemp ) {
            $cmd =
"curl --max-time 30 --silent $FURNACE_LOGIN http://$FURNACE_IP/nothing?xr5=0 > /dev/null 2>&1";
        }
    }
    if ( defined $cmd ) {
        my $now     = time();
        my $lastCmd = $self->{_lastCmd};
        if (
            !(
                   defined($lastCmd)
                && ( $now - ${$lastCmd}[0] < 10 * 60 )
                && $cmd eq ${$lastCmd}[1]
            )
          )
        {
            system($cmd);

            #print STDERR "cmd = " . $cmd . "\n";
            $self->{_lastCmd} = [ $now, $cmd ];
        }
        else {
            #print STDERR "skipping cmd " . $cmd . "\n";
        }
    }
}

1;

