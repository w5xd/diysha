
# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::EventCheckModtronix;

use strict;

sub getCmd {
    my $self         = shift;
    my $temperatureF = shift;
    my $Temp      = shift;
    
    my $cmd;
    #use WirelessGateway to talk to Packet Thermostat
        my $cmdBase =
            $ENV{HTTPD_LOCAL_ROOT}
          . "/../hvac/procWirelessGateway "
          . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
          . " SEND "
          . $self->{_vars}->{FURNACE_NODEID}
          . " ";
        if ( $temperatureF < $Temp ) {
            $cmd = $cmdBase . $self->{_vars}->{FURNACE_BELOW__COMMAND};    # set to NoHP
        }
        elsif ( $temperatureF > $Temp ) {
            $cmd = $cmdBase . $self->{_vars}->{FURNACE_ABOVE__COMMAND};    # set to PasT
        }
    
    
    $cmd;
    
}

1;

