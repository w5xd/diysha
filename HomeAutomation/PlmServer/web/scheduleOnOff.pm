#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#
# package that process POST command to turn on/off the control schedule bits

use strict;
require HomeAutomation::Config;
require HomeAutomation::LightSchedule;
package web::scheduleOnOff;

sub process_request {
	my $self = shift; #not used
	my $c = shift;
	my $r = shift;
	my $msg;
#parameter
my $DEBUG = 0;

#We take arguments. Either as HTTP POST or GET. Find them...
my $buffer;
my @pairs;
my $pair;
my $name;
my $value;
my %FORM;

# Read in text
# Read in text
my $method = $r->method;
$method =~ tr/a-z/A-Z/;
if ( $method eq "POST" ) {
   $buffer = $r->content;
}
elsif ($method eq "GET") {
    $buffer = $r->uri->query;
} else {
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
$msg=<<FirstSectionDone;
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Schedule Setup Results</title>
</head>
<body>
<table border='1'>
<tr><th>Outside</th><th>Inside</th><th>Relay</th><th>Heat Pump Min(F)</th></tr>
FirstSectionDone
;

if ($DEBUG) {
    $msg .= "FORM: <br/> \n";
    while ( my ( $key, $value ) = each(%FORM) ) {
        $msg .= "$key => $value<br/>\n";
    }
}
&HomeAutomation::Config::initialize();
my ( $inside, $outside, $relay ) =
  &HomeAutomation::LightSchedule::getScheduleOnOff();
my @MonitorMessages = &HomeAutomation::LightSchedule::getMonitorMessages();

if ( defined( $FORM{Update} )
    && ( $FORM{Update} eq "Update" ) )
{
    my $nvI;
    my $nvO;
    my $nvR;
    my $nHP;
    my $doS = 0;
    if ( defined( $FORM{InsideSchedule} ) ) {
        $nvI = $FORM{InsideSchedule};
        if ( $nvI ne "" ) { $inside = $nvI; $doS = 1; }
    }
    if ( defined( $FORM{OutsideSchedule} ) ) {
        $nvO = $FORM{OutsideSchedule};
        if ( $nvO ne "" ) { $outside = $nvO; $doS = 1; }
    }
    if ( defined( $FORM{RelaySchedule} ) ) {
        $nvR = $FORM{RelaySchedule};
        if ( $nvR ne "" ) { $relay = $nvR; $doS = 1; }
    }
    if ($doS) {
        &HomeAutomation::LightSchedule::turnScheduleOnOff( $inside, $outside,
            $relay );
    }
    if ( defined( $FORM{HeatPump} ) ) {
        $nHP = $FORM{HeatPump};
        if ( $nHP ne "" ) {
            &HomeAutomation::Config::HEATPUMP_MIN_TEMPERATURE_F($nHP);
        }
    }
}

( $inside, $outside, $relay ) =
  &HomeAutomation::LightSchedule::getScheduleOnOff();
$msg .= "<tr><td>"
  . ( $outside ? "Active" : "Inactive" ) . "</td>" . "<td>"
  . ( $inside  ? "Active" : "Inactive" ) . "</td>" . "<td>"
  . ( $relay   ? "Active" : "Inactive" ) . "</td>" . "<td>"
  . &HomeAutomation::Config::HEATPUMP_MIN_TEMPERATURE_F()
  . "</td></tr>\n"
  . "</table>\n";

my $j = 0;
foreach (@MonitorMessages) {
	$msg .= "<pre>\n" if ($j == 0);
        my $i = 0;
        foreach (split (/\n/, $_) ) {
        $msg .= "&nbsp;&nbsp;&nbsp;" if ($i != 0);
        $msg .= $_ . "\n";
        $i += 1;
    }
    $j += 1;
}
$msg .= "</pre>\n" if ($j != 0);

$msg .=<<Form_print_done7;
</body>
</html>
Form_print_done7
;
my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
  $response->header("Content-type" => "text/html");
  $response->content($msg);
  $c->send_basic_header;
  $c->send_response($response);
}
1;
