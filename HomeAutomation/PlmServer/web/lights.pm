#!/usr/local/bin/perl
#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
# script that maintains HTML form to to display state of and control Insteon devices
# via its http interface.

# download and install
use strict;
use MIME::Base64;
use File::Basename;
require PowerLineModule::Modem;
require HomeAutomation::HouseConfigurationInsteon;

package web::lights;
sub process_request {
	my $self = shift; #not used
	my $c = shift;
	my $r = shift;
	my $msg;
#parameter
my $DEBUG = 0;

# HouseConfiguration.ini settings
my $iVars = HomeAutomation::HouseConfigurationInsteon->new();
my %configHash = %{$iVars->allVars()};

my $ModemDevice = $iVars->get("INSTEON_Modem");

if ($DEBUG) {
    print STDERR 
       " lights ModemDevice="
      . $ModemDevice . "\n";
}

my $defaultEnable = $configHash{LIGHTS_PAGE_default};
if ( !defined($defaultEnable) )   { $defaultEnable = 1; }
if ( lc $defaultEnable eq "yes" ) { $defaultEnable = 1; }
if ( lc $defaultEnable eq "no" )  { $defaultEnable = 0; }

#parallel arrays, i.e., push each of them the same amount
my @DimmerAddrs;
my @DimmerNames;
my @DimmerPagePos;

my $curPushIdx = 0;
my %sortHash   = ();
foreach my $key ( keys %{ $iVars->insteonIds() } ) {
	#for each insteon ID string...
    my $insteonVars = $iVars->insteonDevVars();
    my $enable = $insteonVars->{ $key . "_OnLightsPage" };
    if    ( !defined($enable) )   { $enable = $defaultEnable; }
    elsif ( lc $enable eq "yes" ) { $enable = 1; }
    elsif ( lc $enable eq "no" )  { $enable = 0; }

    my $pos = $insteonVars->{ $key . "_LightsPagePos" };

    my $lbl = $insteonVars->{ $key . "_label" };
    if ( !defined($lbl) ) { $lbl = $key; }    #insteon address is default label

    my $ord = $insteonVars->{ $key . "_LightsPageOrder" };
    if ( !defined($ord) ) {
        $ord = 10000000 + $curPushIdx;
    }                                         #synthesize sort ordinal

    if ($DEBUG) {
        print STDERR "lights "
          . $key . ", \""
          . $lbl . "\", "
          . $enable. ", "
          . $curPushIdx. ", "
          . $ord . ", "
          . $pos . "\n";
    }

    if ($enable) {
        push( @DimmerAddrs,   $key );
        push( @DimmerNames,   $lbl );
        push( @DimmerPagePos, $pos );
        $sortHash{$ord+0} =
          $curPushIdx++;    #duplicate LightsPageOrder settings are lost
    }
}

# these arrays will also be parallel to the previous ones...
my @DimmerVals;
my @DimmerHandles;

#We're a CGI script.
#We take arguments. Either as HTTP POST or GET. Find them...
my $buffer="";
my @pairs;
my $pair;
my $name;
my $value;
my $fromCache = 0;
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
sub StartHtml() {
return <<FirstSectionDone;
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Dimmer Controls</title>
<SCRIPT TYPE="text/javascript">
<!--
// copyright 1999 Idocs, Inc. http://www.idocs.com
// Distribute this script freely but keep this notice in place
function numbersonly(myfield, e, dec)
{
var key;
var keychar;

if (window.event)
   key = window.event.keyCode;
else if (e)
   key = e.which;
else
   return true;
keychar = String.fromCharCode(key);

// control keys
if ((key==null) || (key==0) || (key==8) || 
    (key==9) || (key==13) || (key==27) )
   return true;

// numbers
else if ((("0123456789").indexOf(keychar) > -1))
   return true;
else
   return false;
}
//-->
</SCRIPT>    
</head>
<body>
FirstSectionDone
}
if ($DEBUG) {
    $msg = StartHtml();
    $msg .= "FORM: <br/> \n";
    while ( my ( $key, $value ) = each(%FORM) ) {
        $msg .= "$key => $value<br/>\n";
    }
}

my $Modem = PowerLineModule::Modem->new( $ModemDevice, 0, "" );
if ( $Modem->openOk() == 0 ) {
    if ( !$DEBUG ) { $msg = &StartHtml; }
    $msg .= "Oops, no modem device\n";
    if ( !$DEBUG ) { return 0; }
}
else {
    foreach (@DimmerAddrs) {
        push( @DimmerHandles, $Modem->getDimmer($_) );
    }
    if ( defined( $FORM{Update} ) && ( $FORM{Update} eq "Update" ) ) {
        $fromCache = 0;
        if ( !$DEBUG ) {
            $msg .= "Location: " . File::Basename::basename($0) . "\n\n";
        }
        my $i = 0;
	#the sort is to honor the user's LightsPageOrder setting
        foreach my $k ( sort {$a <=> $b} ( keys %sortHash ) ) {
            my $idx = $sortHash{$k};
            my $cellName = "DimmerNewVal" . ( $i + 1 );
            if ( defined( $FORM{"$cellName"} ) ) {
                my $new_val = $FORM{"$cellName"};
                if ( ( $new_val ne "" ) && ( $new_val >= 0 ) ) {
                    if ( $new_val > 255 ) { $new_val = 255; }
                    my $dimmer = $DimmerHandles[$idx];
                    $dimmer->setValue($new_val);
                    if ($DEBUG) {
                        $msg .= "cell " . $cellName . "= " . $new_val . "<br/>\n";
                    }
                }
            }
            $i++;
        }
        if ( !$DEBUG ) { return 0; }
    }
    elsif ( !$DEBUG ) { &StartHtml; }
}

foreach (@DimmerHandles) {
    if ( $_ != 0 ) {
        my $dimmer = $_;
        push( @DimmerVals, $dimmer->getValue($fromCache) );
    }
    else { push( @DimmerVals, "error" ); }
}

$msg .=<<Form_print_done2;
<form action="" method="post">
<table border="1">
<tr><th>Location</th><th>current</th><th>change</th></tr>
Form_print_done2

my $i = 0;
foreach my $k ( sort {$a <=> $b} (keys %sortHash )) {
    my $idx = $sortHash{$k};
    my $v   = $DimmerVals[$idx];
    if ( $v < 0 ) { $v = "error"; }
    $i = $i + 1; 
    if ($DEBUG) { $msg .= "<tr><td>";
        $msg .= "key=".$k."idx= ".$idx." v=".$v." i=".$i;
	$msg .= "</td></tr>\n";
    }
    $msg .=<<Form_print_row_done;
<tr>
<td>$DimmerNames[$idx]</td>
<td>$v</td>
<td>  <input name="DimmerNewVal$i" size='3' maxlength='3' 
   onkeypress="return numbersonly(this, event)"/></td>
  </tr>
Form_print_row_done
}
$msg .=<<Form_print_done3;
</table>
<input type="submit" name="Update" value="Update" />
</form>
Form_print_done3

if ($DEBUG) {
    $msg .= "fromCache: " . $fromCache . "<br/>\n";
    $msg .= "TESTING: " . @DimmerAddrs . "<br/>\n";
}
my $colorString = "";
$i           = 0;
foreach (@DimmerVals) {
    if ( defined( $DimmerPagePos[$i] ) ) {
        $colorString .= $DimmerPagePos[$i] . " ";
        if    ( $_ < 0 )    { $colorString .= "red "; }
        elsif ( $_ == 0 )   { $colorString .= "black "; }
        elsif ( $_ <= 64 )  { $colorString .= "\"rgb(0, 0, 128)\" "; }
        elsif ( $_ <= 128 ) { $colorString .= "\"rgb(0, 150, 0)\" "; }
        elsif ( $_ <= 192 ) { $colorString .= "yellow "; }
        elsif ( $_ < 255 )  { $colorString .= "gray90 "; }
        else                { $colorString .= "\"rgb(255,20,150)\" "; }

        if ($DEBUG) {
            $msg .= "value  is " . $_ . "<br/>\n";
        }
    }
    $i++;
}
if ($DEBUG) {
    $msg .= $colorString . "<br/>\n";
}
else {
    $msg .= '<img src="data:image/gif;base64,';

    my $AnnotatedGif;
    open( AnnotatedGif, "-|",
            "/usr/local/bin/perl \""
          . $ENV{HTTPD_LOCAL_ROOT}
          . "/cgi-bin/AnnotateFromLights\" "
          . $colorString )
      or exit 0;
    binmode AnnotatedGif;
    my $buf;
    while ( read( AnnotatedGif, $buf, 60 * 57 ) ) {
        $msg .= MIME::Base64::encode_base64($buf);
    }

    $msg .=<<Form_print_done5;
" alt='house drawing' height='100%' width='100%'/>
Form_print_done5
}

$msg .=<<Form_print_done6;
</body>
</html>
Form_print_done6
my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
  $response->header("Content-type" => "text/html");
  $response->content($msg);
  $c->send_basic_header;
  $c->send_response($response);
}
1;
