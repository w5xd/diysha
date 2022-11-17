
# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::EventCheckModtronix;
use base ("hvac::EventCheckEheat");
use strict;

sub getCmdMin {
    my $self         = shift;
    my $temperatureF = shift;
    my $minTemp      = shift;
    
    my $cmd;
    my $FURNACE_LOGIN = $self->{_vars}->{FURNACE_LOGIN};
    if ( defined($FURNACE_LOGIN) && $FURNACE_LOGIN ne "" )
    {                                   #use curl to talk to modtronix
        my $FURNACE_IP = $self->{_vars}->{FURNACE_IP};
        if ( $temperatureF < $minTemp ) {
            $cmd =
"curl --max-time 30 --silent $FURNACE_LOGIN http://$FURNACE_IP/nothing?xr5=1 > /dev/null 2>&1";
        }

        #note that $temperatureF == $minTemp is NOT processed
        elsif ( $temperatureF > $minTemp ) {
            $cmd =
"curl --max-time 30 --silent $FURNACE_LOGIN http://$FURNACE_IP/nothing?xr5=0 > /dev/null 2>&1";
        }
    }
    
    $cmd;
    
}

1;

