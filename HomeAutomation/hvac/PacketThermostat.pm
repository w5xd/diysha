
# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::PacketThermostat;
use base ("hvac::EventCheckEheat");
use strict;

sub getCmdDoNotCall {
    my $self         = shift;
    my $temperatureF = shift;
    my $Temp         = shift;

    my $cmd;

    #use WirelessGateway to talk to Packet Thermostat
    my $cmdBase =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../hvac/procWirelessGateway "
      . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
      . " SEND "
      . $self->{_vars}->{FURNACE_NODEID} . " ";
    if ( $temperatureF < $Temp ) {
        $cmd =
          $cmdBase . $self->{_vars}->{FURNACE_BELOW__COMMAND};    # set to NoHP
    }
    elsif ( $temperatureF > $Temp ) {
        $cmd =
          $cmdBase . $self->{_vars}->{FURNACE_ABOVE__COMMAND};    # set to PasT
    }

    $cmd;
}

sub getCmd {
    my $self         = shift;
    my $temperatureF = shift;
    my $Temp         = shift;
    my $cmd;

    #use WirelessGateway to talk to Packet Thermostat
    my $cmdBase =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../hvac/procWirelessGateway "
      . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
      . " SEND "
      . $self->{_vars}->{FURNACE_NODEID} . " ";
    if ( $temperatureF < $Temp ) {
    }
    elsif ( $temperatureF > $Temp ) {
    }

    $cmd;
}

sub process_request {
    my $self = shift;
    my $c    = shift;
    my $r    = shift;
    my $msg;

    #parameter
    my $DEBUG            = 1;
    my $MIN_TEMP_SETTING = 45;
    my $MAX_TEMP_SETTING = 95;

    #We take arguments. Either as HTTP POST or GET. Find them...
    my $buffer;
    my @pairs;
    my $pair;
    my $name;
    my $value;
    my %FORM;

    # Read in text
    my $method = $r->method;
    $method =~ tr/a-z/A-Z/;
    if ( $method eq "POST" ) {
        $buffer = $r->content;
    }
    elsif ( $method eq "GET" ) {
        $buffer = $r->uri->query;
    }
    else {
        $c->send_error(HTTP::Status::HTTP_FORBIDDEN);
        return;
    }

    # Split information into name/value pairs
    @pairs = split( /&/, $buffer );
    foreach $pair (@pairs) {
        ( $name, $value ) = split( /=/, $pair );
        $value =~ tr/+/ /;
        $value =~ s/%(..)/pack("C", hex($1))/eg;
        $FORM{$name} = $value;
    }

    # required http header cuz we're CGI
    $msg = <<FirstSectionDone;
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Packet Thermostat</title>
</head>
<body>
FirstSectionDone

    if ($DEBUG) {
        $msg .= "FORM: <br/> \n";
        while ( my ( $key, $value ) = each(%FORM) ) {
            $msg .= "$key => $value<br/>\n";
        }
    }

    $msg .= <<Form_print_done1;
<form action="" method="POST">
<input type="hidden" name="hvac_was" value="68" />
<table border="1">
<tr><th>Mode</th><th>Fan</th><th>Target</th>
<th></th>
</tr>
<tr>
<td align='center'>
<select name="thermostat_mode" size=1>
<option >Pass Through</option>
<option >No Heat pump</option>
<option >Heat</option>
<option >eHeat</option>
<option >Cool</option>
</select>
</td>
<td align='center'>
<select name="fan_mode" size=1>
<option >Auto</option>
<option >Continuous</option>
</select>
</td>
<td align='center'>
<select name="temperature_setting" size=1>
Form_print_done1

    for (
        my $temperature = $MIN_TEMP_SETTING ;
        $temperature <= $MAX_TEMP_SETTING ;
        $temperature++
      )
    {
        $msg .= "<option";
        $msg .= ">$temperature</option>\n";
    }

    $msg .= <<Form_print_done2;
</select>&deg;F<br/>
Form_print_done2

    $msg .= <<Form_print_done3;
</td>
<td align="center">
<input type="reset" name="Reset" value="Undo"/><br/>
</td>
</tr>
<tr>
<td colspan='4' align="center">
<input type="submit" name="submit" 
   value="Set thermostat to these settings now!"/>
</td>
</tr>
</table>
</form>

<form action="" 
 onsubmit="return confirm('Will set the thermostat clock to now. OK?');" 
 method="POST">
<p align="center">
<input type="submit" name="sync" value="Synchronize thermostat clock" />
</p>
</form>
<center><font size=+1><b>Thermostat Control</b></font></center>
Form_print_done3

    $msg .= <<Form_print_done7;
</body>
</html>
Form_print_done7

    my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
    $response->header( "Content-type" => "text/html" );
    $response->content($msg);
    $c->send_response($response);
}

1;

