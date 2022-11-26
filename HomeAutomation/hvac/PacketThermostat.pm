
# perl class to call the various classes that can report outdoor temperature
# HouseConfiguration.ini declares them in [SENSOR_MONITOR_STARTUP]

package hvac::PacketThermostat;
use base ("hvac::EventCheckEheat");
use strict;
use feature qw(switch);

#html GUI has 5 entries, Pass-through, no-heat-pump, heat, wheat, cool
our @MapGuiMode = (
    [ "Pass Through", 0, 0 ],    #0
    [ "No Heat pump", 1, 0 ],    #1
    [ "Heat",         2, 0 ],    #2
    [ "eHeat",        2, 1 ],    #3
    [ "Cool",         3, 0 ],    #4
);

sub getCmd {
    my $self         = shift;
    my $temperatureF = shift;
    my $Temp         = shift;
    my $cmd;

    if ( $temperatureF > 0 && defined( $self->{_read_from_tstat} ) ) {
        my $tstatMode = $self->{_thermostat_mode};

        #use WirelessGateway to talk to Packet Thermostat
        my $cmdBase =
            $ENV{HTTPD_LOCAL_ROOT}
          . "/../hvac/procWirelessGateway "
          . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
          . " SEND "
          . $self->{_vars}->{FURNACE_NODEID} . " ";
        if ( $temperatureF < $Temp ) {
            if ( $tstatMode == 0 ) {
                $cmd = $cmdBase . "HVAC TYPE=1 MODE=0";
                $self->{_thermostat_mode} = 1;
            }
            elsif ( $tstatMode == 2 ) {
                $cmd = $cmdBase . "HVAC TYPE=2 MODE=1";
                $self->{_thermostat_mode} = 3;
            }
        }
        elsif ( $temperatureF > $Temp ) {
            if ( $tstatMode == 1 ) {
                $cmd = $cmdBase . "HVAC TYPE=0 MODE=0";
                $self->{_thermostat_mode} = 0;
            }
            elsif ( $tstatMode == 3 ) {
                $cmd = $cmdBase . "HVAC TYPE=2 MODE=0";
                $self->{_thermostat_mode} = 2;
            }
        }
        if ( defined($cmd) && defined( $self->{_read_from_tstat} ) ) {
            delete( $self->{_read_from_tstat} );
        }
    }

    $cmd;
}

sub next_hvac_line {
    my $self   = shift;
    my $line   = shift;
    my $scolon = index( $line, " S:" );
    my $idxTgt = index( $line, " Tt:" );
    my @all    = split( " ", $line );
    if ( ( scalar @all > 0 ) && $all[0] == $self->{_vars}->{FURNACE_NODEID} ) {
        if ( $idxTgt >= 0 ) {
            my $sub    = substr( $line, $idxTgt + 4 );
            my @spl    = split( " ", $sub );
            my $target = int( 10.0 * $spl[0] );
            $self->{_targetTempCx10} = $target;
        }

        if ( $scolon >= 0 ) {
            my $sub = substr( $line, $scolon );
            chomp $sub;
            my @vals = split( ":", $sub );
            if ( scalar @vals >= 4 ) {
                my $t_type = $vals[1];
                my $t_mode = $vals[2];
                my $f_mode = $vals[3];
                my $i      = 0;
                foreach (@MapGuiMode) {
                    if ( $t_type == @{$_}[1] && $t_mode == @{$_}[2] ) {
                        $self->{_thermostat_mode} = $i;
                        $self->{_fan_mode} =
                          $f_mode eq '1'
                          ? 1
                          : ( $f_mode eq '0' ? 0 : undef );
                        $self->{_read_from_tstat} = 1;
                        last;
                    }
                    $i += 1;
                }
            }
        }
    }
}

sub process_request {
    my $self = shift;
    my $c    = shift;
    my $r    = shift;
    my $msg;

    #parameter
    my $DEBUG            = 0;
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
    if ( !defined($buffer) ) { $buffer = ""; }
    @pairs = split( /&/, $buffer );
    foreach $pair (@pairs) {
        ( $name, $value ) = split( /=/, $pair );
        $value =~ tr/+/ /;
        $value =~ s/%(..)/pack("C", hex($1))/eg;
        $FORM{$name} = $value;
    }

    my @commands;

    #use WirelessGateway to talk to Packet Thermostat
    my $cmdBase =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../hvac/procWirelessGateway "
      . $self->{_vars}->{FURNACE_GATEWAY_DEVICE}
      . " SEND "
      . $self->{_vars}->{FURNACE_NODEID} . " ";

    #Do a time sync command if POST asks us too
    if ( defined( $FORM{sync} ) ) {    #user wants the clock synchronized
        (
            my $sec,  my $min,  my $hour, my $mday, my $mon,
            my $year, my $wday, my $yday, my $isdst
        ) = localtime( time + 30 );    # round up to next minute
        $year += 1900;
        $mon  += 1;
        my $setting = "\"T="
          . $year . " "
          . $mon . " "
          . $mday . " "
          . $hour . " "
          . $min . " 0 "
          . $wday . "\"";
        push( @commands, $cmdBase . $setting );
    }
    elsif (
           defined( $FORM{commit} )
        && defined( $self->{_read_from_tstat} )
        && $self->{_thermostat_mode} >= 2  )
    {
        push( @commands, $cmdBase . "HVAC COMMIT" );
    }
    elsif ( defined( $FORM{submit} ) )
    {    #user wants to send the thermostat a command
        if (   defined( $FORM{thermostat_mode} )
            && defined( $FORM{hvac_was} )
            && defined( $FORM{temperature_setting} )
            && defined( $FORM{fan_mode} ) )
        {
            my $tmode = $FORM{thermostat_mode};
            if ( $tmode >= 0 && $tmode <= 4 ) {
                my $m = $self->{_thermostat_mode};
                if ( !defined($m) || $m != $tmode ) {
                    $self->{_thermostat_mode} = $tmode;
                    my $cmd =
                        $cmdBase
                      . "HVAC TYPE="
                      . $MapGuiMode[$tmode][1]
                      . " MODE="
                      . $MapGuiMode[$tmode][2];
                    push( @commands, $cmd );
                }
            }
            my $val = $FORM{temperature_setting};
            if ( $val ne "" && $val >= 70 && $val <= 400 && $tmode >= 2 ) {
                my $m = $self->{_targetTempCx10};
                if ( !defined($m) || $m != $val ) {
                    my $cmd = $cmdBase . "HVAC_SETTINGS " . $val;
                    push( @commands, $cmd );
                    $self->{_targetTempCx10} = $val;
                }
            }
            $val = $FORM{fan_mode};
            if ( $val >= 0 && $val <= 1 ) {
                my $m = $self->{_fan_mode};
                if ( $tmode >= 2 && ( !defined($m) || $m != $val ) ) {
                    my $cmd = $cmdBase . "HVAC FAN=";
                    $cmd .= ( $val != 0 ) ? "ON" : "OFF";
                    push( @commands, $cmd );
                    $self->{_fan_mode} = $val;
                }
            }

            if ( scalar(@commands) && defined( $self->{_read_from_tstat} ) ) {
                delete $self->{_read_from_tstat};
            }
        }
    }
    foreach my $cmd (@commands) {
        my $ok = 0;
        print STDERR "To thermostat \"" . $cmd . "\"\n";
        my @loop = ( 1 .. 4 );
        for (@loop) {
            my ( $my_reader, $my_writer );
            my $pid = IPC::Open2::open2( $my_reader, $my_writer, $cmd );
            $my_writer->autoflush(1);
            $my_reader->autoflush(1);
            close $my_writer;
            while ( my $line = <$my_reader> ) {
                my @sp = split( " ", $line );
                for (@sp) {
                    if ( $_ eq "ACK" ) { $ok = 1; last; }
                }
            }
            close $my_reader;
            if ($ok) { last; }
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

    my $targetTemp      = $self->{_targetTempCx10};
    my $fanMode         = $self->{_fan_mode};
    my $thermostat_mode = $self->{_thermostat_mode};
    my $s               = "";
    if ( !defined($thermostat_mode) ) {
        $thermostat_mode = -1;
        $s               = "<option value='-1'></option>";
    }
    if ( !defined($thermostat_mode) || ( $thermostat_mode < 2 ) ) {
        undef $targetTemp;
        undef $fanMode;
    }
    my $s0 = "";
    my $s1 = "";
    my $s2 = "";
    my $s3 = "";
    my $s4 = "";
    given ($thermostat_mode) {
        when (0) { $s0 = "selected"; }
        when (1) { $s1 = "selected"; }
        when (2) { $s2 = "selected"; }
        when (3) { $s3 = "selected"; }
        when (4) { $s4 = "selected"; }
    }
    my $fm = "";
    if ( !defined($fanMode) ) {
        $fanMode = -1;
        $fm      = "<option value='-1'></option>";
    }
    my $fm0 = "";
    my $fm1 = "";
    given ($fanMode) {
        when (0) { $fm0 = "selected"; }
        when (1) { $fm1 = "selected"; }
    }
    my $fromTstat = defined( $self->{_read_from_tstat} ) ? "." : "";

    $msg .= <<Form_print_done1;
<form action="" method="POST">
<input type="hidden" name="hvac_was" value="$thermostat_mode" />
<table border="1">
<tr><th>Mode</th><th>Fan</th><th>Target</th>
<th>$fromTstat</th>
</tr>
<tr>
<td align='center'>
<select name="thermostat_mode" size=1>
$s
<option value="0" $s0 >$MapGuiMode[0][0]</option>
<option value="1" $s1 >$MapGuiMode[1][0]</option>
<option value="2" $s2 >$MapGuiMode[2][0]</option>
<option value="3" $s3 >$MapGuiMode[3][0]</option>
<option value="4" $s4 >$MapGuiMode[4][0]</option>
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

    if ( !defined($targetTemp) || $targetTemp == 0 ) {
        $msg .= "<option></option>\n";
    }
    for (
        my $temperature = $MIN_TEMP_SETTING ;
        $temperature <= $MAX_TEMP_SETTING ;
        $temperature++
      )
    {
        my $thisTempCx10 = int( ( $temperature - 32 ) * 50 / 9 );
        $msg .= "<option value='" . $thisTempCx10 . "'";
        if ( defined($targetTemp) && ( $thisTempCx10 == $targetTemp ) ) {
            $msg .= " selected";
        }
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
<form action="" 
 method="POST">
<p>
<input type="submit" name="commit" value="Persist" />
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

