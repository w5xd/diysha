#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::LightSchedule;

use strict;
use threads;
use Digest::MD5 qw(md5_hex);
require AppConfig;
require IO::String;
require HomeAutomation::HouseConfigurationInsteon;
require HomeAutomation::InsteonMonitorMessage;

#here is the plan...
# We get called exactly once after Apache startup on our backgroundThread entry point.
# As long as we can talk to the PowerLineModem, we'll never exit.
# We poll on a timer (maybe 20 to 60 seconds) every poll cycle we decide whether we should
# change the setting on any of the lights we control.
# The lights are all outside lights to be turned on close to dusk and off close to dawn.
# "Close to" is within some minutes before/after sunset on a uniform random distribution during that window.
# In the morning, it is within some window after sunrise, we'll turn them off.
# For the sake of randomness, every light has its own schedule.

# Some state is available to other threads. But thread::shared is not used
# because mod_perl launches multiple perl interpreters, and thread::shared
# does not see "across" interpreters. So all state that needs to be shared
# is written to disk. At this writing, all in simple text files.
#
my $DEBUG = 0;
my @Sunrises;
my @Sunsets;
my $yearOfSunrises;
my $TimeZoneOffset;
my $RANDOMRANGE = 30 / 60;
my $RESPECT_TO_SUNRISE =
  -15 / 60;    # Start the turn-off range 15 minutes before local sunrise
my $RESPECT_TO_SUNSET =
  -15 / 60;    # Start the turn-on range 15 minutes before local sunset
my $IN_RESPECT_TO_SUNRISE = -2;    #center before sunrise

sub turnScheduleOnOff {
	# the state of the scheduler is "published" on disk in some flag files
	# the existence of the file means the flag is ON
    my $DoInside  = shift == 0 ? 0 : 1;
    my $DoOutside = shift == 0 ? 0 : 1;
    my $DoRelay   = shift == 0 ? 0 : 1;
    my $runDir = $ENV{HTTPD_LOCAL_ROOT} . "/run";
    if ($DoInside) { open FH, ">$runDir/DoInside"; close FH; }
    else { unlink "$runDir/DoInside";}
    if ($DoOutside) { open FH, ">$runDir/DoOutside"; close FH; }
    else { unlink "$runDir/DoOutside";}
    if ($DoRelay) { open FH, ">$runDir/DoRelay"; close FH; }
    else { unlink "$runDir/DoRelay";}
    print STDERR "DoInside = "
      . $DoInside
      . " DoOutside= "
      . $DoOutside
      . " DoRelay = "
      . $DoRelay . "\n";
}

sub getScheduleOnOff {
    my $runDir = $ENV{HTTPD_LOCAL_ROOT} . "/run";
    return ( (-e "$runDir/DoInside"), (-e "$runDir/DoOutside"), (-e "$runDir/DoRelay") );
}

sub getMonitorMessages {
    # The monitor state (the last thing heard from instean devices)
    # is gathered up from various on-disk files.
    my %Monitors;
    # ini file defines what to look for in insteon EventLog,
    # and how to label each one.
    my $iCfg    = HomeAutomation::HouseConfigurationInsteon->new();
    my $dev     = $iCfg->get("INSTEON_Modem");
    my $key;
    foreach $key ( keys %{ $iCfg->insteonIds() } ) {
        my $devVars      = $iCfg->insteonDevVars();
        my $monitor = $devVars->{ $key. "_monitor" };
        if (defined($monitor)) {
            my $lbl = $devVars->{ $key. "_label" };
            $lbl = $key if (!defined($lbl));
            my $hashing = $devVars->{$key. "_fileKey"};
            $hashing = md5_hex($lbl) if (!defined($hashing));
            print STDERR "getMonitorMessages $lbl is $hashing\n" if ($DEBUG);
            $Monitors{$hashing} = HomeAutomation::InsteonMonitorMessage->new($lbl);
        }
    }
    # parse the EventLog.txt file, passing the events to the appropriate monitors.
    if (open FH, "$ENV{HTTPD_LOCAL_ROOT}/htdocs/insteon/EventLog.txt") {
        while (<FH>) {
           chomp;
           (my $key, my $time, my $cmd1, my $group) = split("\t");
           print STDERR "getMonitorMessages read: " .$_ ."\n" if ($DEBUG);
           if (defined($key) && defined ($time) && defined ($cmd1) && defined ($group))
           {
               my $mon = $Monitors{$key};
               $mon->onEvent($time, $cmd1, $group) if (defined($mon));
           } else { print STDERR "getMonitorMessages split didn't work: ".$_."\n";}
        }
        close FH;
    }
    
    my @MonitorMessages;
    foreach (keys(%Monitors)) {
        push (@MonitorMessages, $Monitors{$_}->statusMessage());
    }
    return @MonitorMessages;
}

sub backgroundThread {

    my $Modem   = shift;    #first arg is PLM modem
                            #$_ is array of references to arrays
    my $args    = shift;    #Outside switches
    my $argsIn  = shift;    #inside dimmers
    my $argsRly = shift;    #SpecialRelay

    {
       my $DoInside  = shift;     #these are the way defaults are set as of Apr 2013
       my $DoOutside = shift;
       my $DoRelay   = shift;
       turnScheduleOnOff($DoInside, $DoOutside, $DoRelay);
    }

    my $monitors = shift;

    # $args[$i] are handles to the PowerLineModem Dimmer objects
    my @currentValues        = ();
    my @randomOffset         = ();
    my @currentValuesI       = ();
    my @currentValuesSpecial = ();
    my @randomOffsetI        = ();
    my @randomDimmer         = ();

    #get our state variables to the correct size
    for ( my $i = 0 ; $i < scalar( @{$args} ) ; $i++ ) {
        push( @currentValues, -10 );    #unknown state
        push( @randomOffset,  0 );
    }
    for ( my $i = 0 ; $i < scalar( @{$argsIn} ) ; $i++ ) {
        push( @currentValuesI, -10 );    #unknown state
        my @randoms = ( 0, 0, 0, 0 );
        push( @randomOffsetI, \@randoms );
        push( @randomDimmer,  0 );
    }
    for ( my $i = 0 ; $i < scalar( @{$argsRly} ) ; $i++ ) {
        push( @currentValuesSpecial, 0 );
    }

    my $setRandomnessForDay = -1;

    $Modem->setMonitorState(1);          # tell PLM to queue notifications
    my $runDir = $ENV{HTTPD_LOCAL_ROOT} . "/run";

    # loop forever
    for ( my $pollCount = 0 ; $pollCount <= 0 ; ) {
	my $DoInsideLocal; my $DoOutsideLocal; my $DoRelayLocal;
	{
		$DoInsideLocal = (-e "$runDir/DoInside");
		$DoOutsideLocal = (-e "$runDir/DoOutside");
		$DoRelayLocal = (-e "$runDir/DoRelay");
	}
        LoadSunriseTable();    #update table first time and on New Year's day
        my $t = time + $TimeZoneOffset;
        (
            my $sec,  my $min,  my $hour, my $mday, my $mon,
            my $year, my $wday, my $yday, my $isdst
        ) = gmtime($t);
        my $origHour = $hour;
        $hour += $min / 60;
        my $currentSunrise = $Sunrises[ $mday - 1 ][$mon];
        my $currentSunset  = $Sunsets[ $mday - 1 ][$mon];

        # in local time,

        if ( $setRandomnessForDay != $mday ) {
            print STDERR "LightSchedule setting randomness for today: " . $mday
              . "\n";
            for my $i ( 0 .. scalar(@randomOffset) ) {
                $randomOffset[$i] = rand($RANDOMRANGE);
            }
            for my $i ( 0 .. scalar(@randomDimmer) ) {
		    # bunch of magic numbers here...the width of the distribution
                $randomOffsetI[$i]->[0] = rand(3.0);     #morning ON random
                $randomOffsetI[$i]->[1] = rand(1.5);     #morning OFF random
                $randomOffsetI[$i]->[2] = rand(0.75);    #evening ON
                $randomOffsetI[$i]->[3] = rand(1.5);     #evening OFF
                $randomDimmer[$i] =
                  rand( 32 + 64 + 127 ) * rand(1.0)
                  ;    #dimmer value itself, weighted towards zero
            }
            $setRandomnessForDay = $mday;
        }

        if ($DoOutsideLocal) {
            for ( my $i = 0 ; $i < scalar( @{$args} ) ; $i++ ) {

                # set the light ON at dusk +/- random and OFF at sunrise
                my $valForThisLightNow = 255;
                if (
                    $hour > (
                        $currentSunrise +
                          $RESPECT_TO_SUNRISE +
                          $randomOffset[$i]
                    )
                  )
                {
                    $valForThisLightNow = 0;
                }
                if ( $hour >
                    ( $currentSunset + $RESPECT_TO_SUNSET + $randomOffset[$i] )
                  )
                {
                    $valForThisLightNow = 255;
                }
                if ( ${$args}[$i] != 0 ) {
                    if ( $valForThisLightNow != $currentValues[$i] ) {
                        print STDERR "At "
                          . $hour
                          . " Changing dimmer "
                          . $i . " to "
                          . $valForThisLightNow
                          . " offset:"
                          . $randomOffset[$i] . "\n";
                        my $dimmer = ${$args}[$i];
                        $dimmer->setValue($valForThisLightNow);
                        $currentValues[$i] = $valForThisLightNow;
                    }
                }
            }
        }

        if ($DoInsideLocal) {
            for ( my $i = 0 ; $i < scalar( @{$argsIn} ) ; $i++ ) {
                # simulate human habitation
                # Times are STANDARD time, regardless of DST time-of-year
                my $valForThisLightNow =
                  0;    # at midnight, inside lights are always off
                        # wakeup time. 4:30AM -> 7:30AM
                if ( $hour > ( 4.5 + $randomOffsetI[$i]->[0] ) ) {
                    $valForThisLightNow = 32 + $randomDimmer[$i];
                }

                # half hour after sunrise + <90 min, turn off
                if ( $hour >
                    ( $currentSunrise + 0.5 + $randomOffsetI[$i]->[1] ) )
                {
                    $valForThisLightNow = 0;
                }
                if ( $hour > ( $currentSunset + $randomOffsetI[$i]->[2] ) ) {
                    $valForThisLightNow = 32 + $randomDimmer[$i];
                }
                if ( $hour > ( 20.5 + $randomOffsetI[$i]->[3] ) )
                {    # off at 8:30PM + < 90m
                    $valForThisLightNow = 0;
                }
                if ( ${$argsIn}[$i] != 0 ) {
                    if ( $valForThisLightNow != $currentValuesI[$i] ) {
                        print STDERR "At "
                          . $hour
                          . " Changing inside dimmer "
                          . $i . " to "
                          . $valForThisLightNow
                          . " offsetw: "
                          . $randomOffsetI[$i]->[0] . ", "
                          . $randomOffsetI[$i]->[1] . ", "
                          . $randomOffsetI[$i]->[2] . ", "
                          . $randomOffsetI[$i]->[3] . "\n";
                        my $dimmer = ${$argsIn}[$i];
                        $dimmer->setValue($valForThisLightNow);
                        $currentValuesI[$i] = $valForThisLightNow;
                    }
                }
            }
        }

        if ($DoRelayLocal) {
            for ( my $i = 0 ; $i < scalar( @{$argsRly} ) ; $i++ ) {
                my $rly = ${$argsRly}[$i];
                if (0) {
                    my $valForNow = 0;    #midnight
                    if ( $hour > 5 )  { $valForNow = -1; }
                    if ( $hour > 8 )  { $valForNow = 1; }
                    if ( $hour > 10 ) { $valForNow = 0; }
                    if ( ${$argsRly}[$i] != 0 ) {
                        if ( $valForNow != $currentValuesSpecial[$i] ) {
                            print STDERR "At "
                              . $hour
                              . " Changing rly "
                              . $i . " to "
                              . $valForNow . "\n";
                            if ( $valForNow == -1 ) {
                                $rly->setFast($valForNow);
                            }
                            else {
                                $rly->setValue($valForNow);
                            }
                            $currentValuesSpecial[$i] = $valForNow;
                        }
                    }
                }
                else {
                    if ( $rly != 0 ) {
                        if ( $origHour != $currentValuesSpecial[$i] ) {
                            $currentValuesSpecial[$i] = $origHour;
                            print STDERR "At  " . $hour . " rly " . $i
                              . " fast off.\n";
                            $rly->setFast(-1);
                        }
                    }
                }
            }
        }

        # dispatch insteon callbacks or wait
        my $evtCount =
          $Modem->monitor(37);   #check slightly less often than once per minute
        if ($DEBUG) { print STDERR "LightSchedule evtCount: ".$evtCount."\n";}
        if ( $evtCount == 0 ) {
            foreach ( @{$monitors} ) { 
		$_->{monitor}->onTimer($_, $Modem); 
	    }
        }
    }

    $Modem->shutdown()
      ;    #will never get here, but this is what would happen if we did
}

sub LoadSunriseTable {
    my $config = AppConfig->new(
        {
            CREATE => 1,
            CASE   => 1,
            GLOBAL => {
                ARGCOUNT => AppConfig::ARGCOUNT_ONE,
            },
        }
    );
    my $cfgFile = $ENV{HTTPD_LOCAL_ROOT} . "/../HouseConfiguration.ini";
    $config->file($cfgFile);
    my %vars = $config->varlist( "^SUNTIMES_", 1 );

    $TimeZoneOffset = $vars{TimeZoneOffset};
    $TimeZoneOffset *= 60 * 60; # convert to seconds
    my $time = time + $TimeZoneOffset;
    my @gmt  = gmtime($time);
    my $yr   = $gmt[5] + 1900;
    if ( ( defined $yearOfSunrises ) && ( $yearOfSunrises == $yr ) ) {
        return 0;
    }    #table is still good
    my $SunriseTable;
    $SunriseTable = IO::String->new;

#result of
# http://aa.usno.navy.mil/cgi-bin/aa_rstablew.pl?FFX=1&type=0&xxy=2012&st=MA&place=Cambridge&ZZZ=END
    print $SunriseTable $vars{Table};

    $SunriseTable->pos(0);    #back to beginning of the file
    my $dayNum        = -1;
    my @localSunrises = ();
    my @localSunsets  = ();
    while (<$SunriseTable>) {
        if ( index( $_, "h m  h m" ) > 0 ) {
            $dayNum = 0;
        }
        if ( $dayNum >= 1 ) {
            my $row = substr $_,
              4;              #remove the day-of-month from beginning of column
            my @sunrises = ();
            my @sunsets  = ();
            for ( my $month = 0 ; $month < 12 ; $month++ ) {
                my $thistime = substr $row, 0, 2;
                $row = substr $row, 2;
                $thistime += ( substr $row, 0, 2 ) / 60;
                $row = substr $row, 3;
                push @sunrises, $thistime;
                $thistime = substr $row, 0, 2;
                $row = substr $row, 2;
                $thistime += ( substr $row, 0, 2 ) / 60;
                $row = substr $row, 4;
                push @sunsets, $thistime;
            }
            push @localSunrises, [@sunrises];
            push @localSunsets,  [@sunsets];
        }
        if ( $dayNum == 31 ) {
            @Sunrises       = @localSunrises;
            @Sunsets        = @localSunsets;
            $yearOfSunrises = $yr;
        }
        if ( $dayNum >= 0 ) { $dayNum++; }
    }

    #debug printout
    if ($DEBUG) {
        print STDERR "Year: " . $yearOfSunrises . "\n";
        for ( my $j = 0 ; $j < scalar(@Sunrises) ; $j++ ) {
            print STDERR "For day " . $j . " sunrises: ";
            my $day1 = $Sunrises[$j];
            for my $k ( 0 .. $#{$day1} ) {
                print STDERR $Sunrises[$j][$k] . ", " . $Sunsets[$j][$k] . " ";
            }
            print STDERR "\n";
        }
    }

    return 0;
}

1;
