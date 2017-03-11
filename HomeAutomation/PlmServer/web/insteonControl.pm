#Copyright (c) 2017 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
# http process POST command to control Insteon devices

use strict;
require PowerLineModule::Modem;
use AppConfig;
package web::insteonControl;

sub process_request {
	my $self = shift; #not used
	my $c = shift;
	my $r = shift;
	my $msg;
	
#parameter
my $DEBUG = 0;

my $config = AppConfig->new(
    {
        CREATE => 1,
        CASE   => 1,
        GLOBAL => {
            ARGCOUNT => AppConfig::ARGCOUNT_ONE,
        },
    }
);
my $cfgFileName = $ENV{HTTPD_LOCAL_ROOT} . "/../HouseConfiguration.ini";
$config->file($cfgFileName);

my $ModemDevice = $config->get("INSTEON_Modem");

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
<title>Dimmer Control Results</title>
</head>
<body>
FirstSectionDone
;

if ($DEBUG) {
    $msg .= "FORM: <br/> \n";
    while ( my ( $key, $value ) = each(%FORM) ) {
        $msg .= "$key => $value<br/>\n";
    }
}

my $Modem = PowerLineModule::Modem->new( $ModemDevice, 0, "" );

if ( $Modem->openOk() == 0 ) {
    $msg .= "Oops, no modem device\n";
}
else {
    if (   defined( $FORM{Update} )
        && ( $FORM{Update} eq "Update" )
        && defined( $FORM{DimmerInsteonId} )
        && defined( $FORM{DimmerValue} ) )
    {
        my $id      = $FORM{DimmerInsteonId};
        my $new_val = $FORM{DimmerValue};
        my $isFan   = $FORM{isFan} eq "yes";
        my $insteonClass   = uc $FORM{insteonClass};
        my $DimmerHandle = 0;
	if ($insteonClass eq "FANLINC") {
            $DimmerHandle = $Modem->getFanlinc($id); }
        elsif ($insteonClass eq "RELAY")  {
	    $DimmerHandle = $Modem->getRelay($id); }
        elsif ($insteonClass eq "X10DIMMER")  {
	    if (defined($new_val) && $new_val ne "")
	    {# don't try to read x10
	        $DimmerHandle = $Modem->getX10Dimmer($id); 
	    }
        }
	else {
	    $DimmerHandle = $Modem->getDimmer($id); }
        if ( $DimmerHandle != 0 ) {
            if ( $new_val ne "" ) {
                my $res;
                if ( !$isFan ) {
                    if ( ( $new_val == -1 ) || ( $new_val == 256 ) ) {
                        $res = $DimmerHandle->setFast($new_val);
                    }
                    else {
                        $res = $DimmerHandle->setValue($new_val);
                    }
                }
                else {
                    $res = $DimmerHandle->setFanSpeed($new_val);
                }
                $msg .= "Set dimmer "
                  . $id . " to "
                  . $new_val
                  . " with result "
                  . $res
                  . "<br/>\n";
            }
            else {
                if ( !$isFan ) {
                    $new_val = $DimmerHandle->getValue(0);
                }
                else {
                    $new_val = $DimmerHandle->getFanSpeed();
                }
                $msg .= "Got dimmer value "
                  . $new_val
                  . " for dimmer id "
                  . $id
                  . "<br/>\n";
            }
        }
        else {
            $msg .= "Oops no dimmer handle<br/>\n";
        }
    }
}

$msg .=<<Form_print_done6;
</body>
</html>
Form_print_done6
;
my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
  $response->header("Content-type" => "text/html");
  $response->content($msg);
  $c->send_response($response);
}
1;
