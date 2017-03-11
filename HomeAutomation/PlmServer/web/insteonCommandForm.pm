#Copyright (c) 2017 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
use strict;
use HTTP::Status qw(:constants);
use HomeAutomation::HouseConfigurationInsteon;
package web::insteonCommandForm;

#parameters are self, http connection and request
sub process_request {
	my $self = shift;
	my $c = shift;
	my $r = shift;

	my $method = $r->method;
	$method =~ tr/a-z/A-Z/;	
	if ($method ne "GET")
	{
	    $c->send_error(HTTP::Status::HTTP_FORBIDDEN);
	    return;
	}

my $DEBUG = 0;
my $iVars = HomeAutomation::HouseConfigurationInsteon->new();

my @DimmerAddrs;
my @DimmerNames;
my @DimmerClasses;
my $defaultEnable = $iVars->allVars()->{LIGHTS_PAGE_defaultCommandPage};
if ($DEBUG) {
    print STDERR "insteonCommandForm defaultenable=" . $defaultEnable . "\n";
}

if    ( !defined($defaultEnable) )  { $defaultEnable = 1; }
elsif ( lc $defaultEnable eq "no" ) { $defaultEnable = 0; }
else                                { $defaultEnable = 1; }

my %sortHash   = ();
my $curPushIdx = 0;
foreach my $key ( keys %{ $iVars->insteonIds() } ) {
    my $insteonVars = $iVars->insteonDevVars();
    my $enable      = $insteonVars->{ $key . "_OnCommandPage" };
    my $className   = $insteonVars->{ $key . "_class" };
    if (!defined($className) || ($className eq "")) { $className = "Dimmer"; }
    if    ( !defined($enable) )   { $enable = $defaultEnable; }
    elsif ( lc $enable eq "yes" ) { $enable = 1; }
    elsif ( lc $enable eq "no" )  { $enable = 0; }

    my $lbl = $insteonVars->{ $key . "_label" };
    if ( !defined($lbl) ) { $lbl = $key; }    #insteon address is default label

    my $ord = $insteonVars->{ $key . "_LightsPageOrder" };
    if ( !defined($ord) ) {
        $ord = 10000000 + $curPushIdx
          ;    #synthesize sort ordinal--hopefully bigger than in ini file
    }

    if ($enable) {
        push( @DimmerAddrs, $key );
        push( @DimmerNames, $lbl );
	push( @DimmerClasses, $className);
        $sortHash{ $ord * 2 } =
          $curPushIdx++;    #duplicate LightsPageOrder settings are lost
        if ( $className eq "Fanlinc" ) {
            push( @DimmerAddrs, $key );
            push( @DimmerNames, $lbl . " (Fan)" );
	    push( @DimmerClasses, $className);
            $sortHash{ 1 + $ord * 2 } = $curPushIdx++;
        }
    }
}
foreach my $key ( keys %{ $iVars->x10Ids() } ) {
    my $x10DevVars = $iVars->x10DevVars();
    my $enable      = $x10DevVars->{ $key . "_OnCommandPage" };
    my $className   = "X10Dimmer";
    if    ( !defined($enable) )   { $enable = $defaultEnable; }
    elsif ( lc $enable eq "yes" ) { $enable = 1; }
    elsif ( lc $enable eq "no" )  { $enable = 0; }

    my $lbl = $x10DevVars->{ $key . "_label" };
    if ( !defined($lbl) ) { $lbl = $key; }    #insteon address is default label

    my $ord = $x10DevVars->{ $key . "_LightsPageOrder" };
    if ( !defined($ord) ) {
        $ord = 10000000 + $curPushIdx
          ;    #synthesize sort ordinal--hopefully bigger than in ini file
    }

    if ($enable) {
        push( @DimmerAddrs, $key );
        push( @DimmerNames, $lbl );
	push( @DimmerClasses, $className);
        $sortHash{ $ord * 2 } =
          $curPushIdx++;    #duplicate LightsPageOrder settings are lost
    }
}
my $msg =<<htmlText1End
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">
<html>
<head>
<title>Insteon Command</title>
<script type="text/javascript">
var optionValues = [
htmlText1End
;
my @sortedKeys = sort { $a <=> $b } ( keys %sortHash);
foreach my $k ( @sortedKeys )  {
    my $idx = $sortHash{$k};
    $msg .= '"' . $DimmerAddrs[$idx] . '", "' . $DimmerClasses[$idx] . '",' . "\r\n";
}

$msg .=<<htmlText2End
];
<!--
// copyright 1999 Idocs, Inc. http://www.idocs.com
// Distribute this script freely but keep this notice in place
function numbersonly(myfield, e, hex)
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
else if ((hex != 0) && ("abcdefABCDEF.".indexOf(keychar) > -1))
    return true;
else if ((hex == 0) && ("-".indexOf(keychar) > -1))
    return true;
else
   return false;
}
function copySelectToInput (element){
    var inBox = document.getElementById("deviceIdInput");
    var option = element.options[element.selectedIndex];
    var optidx = option.value * 2;
    inBox.value = optionValues[optidx];
    var classBox = document.getElementById("idInsteonClass");
    classBox.value = optionValues[1 + optidx];
    var fanBox = document.getElementById("isFanID");
    var selText = option.text;
    var FanIndex = selText.indexOf(" (Fan)");
    fanBox.value = ((FanIndex >= 0) && (FanIndex == selText.length - 6)) ? "yes" : "no";
}
//-->
</script>    
</head>
<body>
    <form action="insteonControl" method="post">
    <table border="1">
        <tr>
            <th>
                Dimmer Insteon hex ID<br /> (aa.bb.cc)
            </th>
            <th>
            </th>
            <th>
                Set to
            </th>
        </tr>
        <tr>
            <td>
                <input id='deviceIdInput' 
                name="DimmerInsteonId" size='8' maxlength='8' 
                onkeypress="return numbersonly(this, event, 1)" />
		<input type='hidden' id='idInsteonClass' name='insteonClass' value='Dimmer' />
		<input type='hidden' id='isFanID' name='isFan' value='no' />
            </td>
            <td align='center'>
            <select name="named_device" id="deviceSelectBox" onchange='copySelectToInput(this)'>
htmlText2End
  ;

$msg .= "<option value='MANUAL' selected></option>\n";

my $i = 0;
foreach my $k ( @sortedKeys )  {
    my $idx = $sortHash{$k};
    $msg .= "<option value='"
      . $i++ . "' text='"
      . $DimmerNames[$idx] . "'>"
      . $DimmerNames[$idx]
      . "</option>\n";
}

$msg .=<<htmlText2End
            </select>
            </td>
            <td>
                <input name="DimmerValue" size='3' maxlength='3' onkeypress="return numbersonly(this, event, 0)" />
            </td>
            <td>
                <input type="submit" name="Update" value="Update" />
            </td>
        </tr>
    </table>
Leave <b>Set to</b> column blank to read dimmer value.<br/>
values 1 through 254 are direct commands to the dimmer.<br/>
values 0 and 255 are translated to group/link commands <i><b>if</b></i> the local PLM has a link to the dimmer.<br/>
values 256 and -1 are translated, respectively, to FAST ON and FAST off.</br>
</body>
</html>
htmlText2End
;
  
my $response = HTTP::Response->new(HTTP::Status::HTTP_OK);
  $response->header("Content-type" => "text/html");
  $response->content($msg);
  $c->send_response($response);
}
1;
