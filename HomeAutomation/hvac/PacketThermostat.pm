
# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::PacketThermostat;
use base ("hvac::EventCheckEheat");
use strict;
use feature qw(switch);

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
    if (!defined($buffer)) { $buffer = ""; }
    @pairs = split( /&/, $buffer );
    foreach $pair (@pairs) {
        ( $name, $value ) = split( /=/, $pair );
        $value =~ tr/+/ /;
        $value =~ s/%(..)/pack("C", hex($1))/eg;
        $FORM{$name} = $value;
    }

#Do a sync command if it asks us too
if ( defined( $FORM{sync} ) ) {    #user wants the clock synchronized
    (
        my $sec,  my $min,  my $hour, my $mday, my $mon,
        my $year, my $wday, my $yday, my $isdst
    ) = localtime( time + 30 );    # round up to next minute
    $year += 1900;
    $mon += 1;
    my $setting = "T=". $year . " " . $mon . " " . $mday . " " . $hour . " " . $min . " 0 " . $wday;
    print STDERR "command=\"" . $setting . "\"\n";
}
elsif ( defined( $FORM{submit} ) )
{    #user wants to send the thermostat a command
    if (   defined( $FORM{thermostat_mode} )
        && defined( $FORM{hvac_was} )
        && defined( $FORM{temperature_setting} )
        && defined( $FORM{fan_mode} ) )
    {
        my $val = $FORM{thermostat_mode};
	if ($val >= 0 && $val <= 4) {$self->{_thermostat_mode} = $val;}
	$val = $FORM{temperature_setting};
	if ($val >= 70 && $val <= 400 ) { $self->{_targetTempCx10} = $val; }
        $val = $FORM{fan_mode};
	if ($val >= 0 && $val <= 1) { $self->{_fan_mode} = $val; }
    }
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

    my $targetTemp = $self->{_targetTempCx10};
    my $thermostat_mode = $self->{_thermostat_mode};
    my $s = "";
    if (!defined($thermostat_mode)) { $thermostat_mode = -1; 
    	$s = "<option value='-1'></option>";}
    my $s0 = ""; my $s1 = ""; my $s2 = ""; my $s3 = ""; my $s4 = "";
    given ($thermostat_mode) {
	    when(0) { $s0 = "selected";}
	    when(1) { $s1 = "selected";}
	    when(2) { $s2 = "selected";}
	    when(3) { $s3 = "selected";}
	    when(4) { $s4 = "selected";}
    }
    my $fanMode = $self->{_fan_mode};
    my $fm = "";
    if (!defined($fanMode)) { $fanMode = -1; 
	    $fm = "<option value='-1'></option>";
    }
    my $fm0 = ""; my $fm1 = "";
    given ($fanMode) {
	   when(0) { $fm0 = "selected"; }
	   when(1) { $fm1 = "selected"; }
    }

    $msg .= <<Form_print_done1;
<form action="" method="POST">
<input type="hidden" name="hvac_was" value="$thermostat_mode" />
<table border="1">
<tr><th>Mode</th><th>Fan</th><th>Target</th>
<th></th>
</tr>
<tr>
<td align='center'>
<select name="thermostat_mode" size=1>
$s
<option value="0" $s0 >Pass Through</option>
<option value="1" $s1 >No Heat pump</option>
<option value="2" $s2 >Heat</option>
<option value="3" $s3 >eHeat</option>
<option value="4" $s4 >Cool</option>
</select>
</td>
<td align='center'>
<select name="fan_mode" size=1>
$fm
<option value="0" $fm0>Auto</option>
<option value="1" $fm1>Continuous</option>
</select>
</td>
<td align='center'>
<select name="temperature_setting" size=1>
Form_print_done1

    if (!defined($targetTemp)) { 
	    $msg .= "<option></option>\n";
    }
    for (
        my $temperature = $MIN_TEMP_SETTING ;
        $temperature <= $MAX_TEMP_SETTING ;
        $temperature++
      )
    {
	my $thisTempCx10 = int(($temperature - 32) * 50 / 9);
        $msg .= "<option value='" . $thisTempCx10 . "'";
	if (defined($targetTemp) && ($thisTempCx10 == $targetTemp)) { $msg .= " selected"; }
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
<p>
<input type="submit" name="sync" value="Synchronize thermostat clock" />
</p>
</form>
<font size=+1><b>Packet Thermostat</b></font>
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

