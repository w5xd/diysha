#Copyright (c) 2017 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::StartMonitor;

# The perl startup routine for HomeAutomation in the perl web server
use strict;
use Digest::MD5 qw(md5_hex);

require PowerLineModule::Modem;
require HomeAutomation::LightSchedule;
require HomeAutomation::HouseConfigurationInsteon;
require HomeAutomation::AllMonitor;
require HomeAutomation::WaterLeakMonitor;
require HomeAutomation::InsteonMonitor;
require HomeAutomation::AlwaysOffRelay;
require HomeAutomation::ScheduledRelay;

use threads;
use threads::shared;
use AppConfig;
use Switch;

my $DEBUG = 0;

sub printDimmerLinks {
    my $Modem = shift;
    if ($DEBUG) { print STDERR "PrintDimmerLinks:" . @_ . "\n"; }
    foreach (@_) {
        $_->startGatherLinkTable();
        $_->getNumberOfLinks();
        $Modem->printLogString( $_->name() . "\n" );
        $Modem->printLogString( $_->printLinkTable() );
    }
    1;
}

sub monitor_cb {    # forward to monitor object
    if ($DEBUG) { print STDERR "monitor_cb " . $_ . "\n"; }
    my $dimmer = $_[0];
    return $dimmer->{monitor}->onEvent(@_);
}
my $initSchedOnce : shared;

sub start {
    my $logfile = shift;
    my $iCfg    = HomeAutomation::HouseConfigurationInsteon->new();
    my $dev     = $iCfg->get("INSTEON_Modem");
    my $Modem   = PowerLineModule::Modem->new( $dev, 2, $logfile );
    my $bck;

    my $doneAlready;
    {
        lock($initSchedOnce);
        $doneAlready   = $initSchedOnce;
        $initSchedOnce = 1;
    }

    if ( !$doneAlready )    #first time through
    {
        if ( $Modem->openOk() == 0 )     {
		print STDERR "Failed to open modem $dev\n";
	}
        else # got a live COM port
        {
            $Modem->setCommandDelay(700)
              ;    #700 msec delay from incoming to outgoing
                   #get modem groups into memory
            $Modem->getModemLinkRecords();

            #assure modem in non-linking state
            $Modem->cancelLinking();
            my @OutsideDimmers;
            my @InsideDimmers;
            my @SpecialRelay;
            my @UnscheduledDimmers;
            my @Monitors;

            my $key;
            my $value;
            my %configHash    = %{ $iCfg->allVars() };
            my $OutsideEnable = $configHash{INSTEON_SCHEDULE_sunsync_outside};
            if ( !defined($OutsideEnable) ) { $OutsideEnable = 1; }
            my $InsideEnable = $configHash{INSTEON_SCHEDULE_sunsync_inside};
            if ( !defined($InsideEnable) ) { $InsideEnable = 1; }
            my $SpecialEnable = $configHash{INSTEON_SCHEDULE_special_relay};
            if ( !defined($SpecialEnable) ) { $SpecialEnable = 0; }

            my $heartbeatHours = $configHash{INSTEON_MONITORS_heartbeat};
            $heartbeatHours = 12 if ( !defined($heartbeatHours) );
            my $monitorEmail = $configHash{INSTEON_MONITORS_email};
            my $monitorLogName =
              $ENV{HTTPD_LOCAL_ROOT} . "/htdocs/insteon/EventLog.txt";
            my %MonitorHash;
            foreach $key ( keys %{ $iCfg->insteonIds() } ) {
                if ($DEBUG) {
                    print STDERR "StartupMonitor key=" . $key . "\n";
                }
                my $allVars      = $iCfg->insteonDevVars();
                my $insteonClass = $allVars->{ $key . "_class" };
                if ( !defined($insteonClass) ) { $insteonClass = "Dimmer"; }
                my $schedule     = $allVars->{ $key . "_schedule" };
                my $acqLinkTable = $allVars->{ $key . "_acquireLinkTable" };
                my $device;
                switch ( uc $insteonClass ) {
                    case "DIMMER"  { $device = $Modem->getDimmer($key); }
                    case "RELAY"   { $device = $Modem->getRelay($key); }
                    case "FANLINC" { $device = $Modem->getFanlinc($key); }
                    case "KEYPAD"  { $device = $Modem->getKeypad($key); }
                    else {
                        print STDERR
                          "StartupMonitor encounted invalid device class "
                          . $insteonClass . "\n";
                    }
                }
                if ( defined($device) ) {
                    if ( $device == 0 ) {
                        print STDERR "StartupMonitor could not instance device "
                          . $key . "\n";
                    }
                    else {
                        if ( defined($schedule) ) {
                            my @scheduleParams = split( ' ', $schedule );
                            switch ( uc shift @scheduleParams ) {
                                case "OUTSIDE" {
                                    push( @OutsideDimmers, $device );
                                }
                                case "INSIDE" {
                                    push( @InsideDimmers, $device );
                                }
                                case "SPECIAL_RELAY" {
                                    my $rly;
                                    if (@scheduleParams) {
                                        unshift( @scheduleParams, $device );
                                        $rly =
                                          HomeAutomation::ScheduledRelay->new(
                                            @scheduleParams);
                                    }
                                    else {
                                        $rly =
                                          HomeAutomation::AlwaysOffRelay->new(
                                            $device);
                                    }
                                    push( @SpecialRelay, $rly );
                                }
                                else {
                                    print STDERR
"StartupMonitor encountered invalid schedule "
                                      . $schedule . "\n";
                                }
                            }
                        }
                        elsif ( !defined($acqLinkTable) ) {
                            push( @UnscheduledDimmers, $device );
                        }

                        #attach a text label to the device
                        my $lbl = $allVars->{ $key . "_label" };
                        if ( !defined($lbl) ) { $lbl = $key; }
                        $device->name($lbl);

                        #override heartbeat?
                        my $hb = $allVars->{ $key . "_heartbeat" };
                        if ( !defined($hb) ) { $hb = $heartbeatHours; }

                        my $monitor = $allVars->{ $key . "_monitor" };
                        my $monObj;
                        if ( defined($monitor) ) {
                            switch ( uc $monitor ) {
                                case "NONE" { }
                                case "ALL" {
                                    $monObj =
                                      HomeAutomation::AllMonitor->new( $hb,
                                        $monitorEmail );
                                }
                                case "WATERLEAK" {
                                    $monObj =
                                      HomeAutomation::WaterLeakMonitor->new(
                                        $hb, $monitorEmail );
                                }
                                case "HEARTBEAT" {
                                    $monObj =
                                      HomeAutomation::InsteonMonitor->new( $hb,
                                        $monitorEmail );
                                }
                                else {
                                    print STDERR
"StartupMonitor encountered invalid monitor "
                                      . $monitor . "\n";
                                }
                            }
                        }
                        if ( defined($monObj) ) {
                            if ($DEBUG) {
                                print STDERR "instanced a monitor\n";
                            }
                            my $hashing = $allVars->{ $key . "_fileKey" };
                            $hashing = md5_hex($lbl) if ( !defined($hashing) );
                            $monObj->fileKey($hashing);
                            $monObj->logFileName($monitorLogName);
                            $monObj->acquireLinkTable($acqLinkTable)
                              if defined($acqLinkTable);
                            $device->monitorCb( \&monitor_cb );
                            push( @Monitors, $device );
                            $device->{monitor} = $monObj;
                            $MonitorHash{$hashing} = $monObj;
                        }
                    }
                }
            }

      #playback saved events...
      #This playback from disk enables the monitor alarms to have lengths longer
      #than the webserver runs. ie if apache is restarted, the monitor still
      #sends the email at the right interval
            if ( open FH, $monitorLogName ) {
                while (<FH>) {
                    chomp;
                    ( my $key, my $time, my $cmd1, my $group ) = split("\t");
                    print STDERR "getMonitorMessages read: " . $_ . "\n"
                      if ($DEBUG);
                    if (   defined($key)
                        && defined($time)
                        && defined($cmd1)
                        && defined($group) )
                    {
                        my $mon = $MonitorHash{$key};
                        $mon->recordEvent( $time, 0, $group, $cmd1 )
                          if ( defined($mon) );
                    }
                    else {
                        print STDERR "StartupMonitor split didn't work: "
                          . $_ . "\n";
                    }
                }
                close FH;
            }

            $Modem->printLogString( $Modem->printLinkTable() );

            printDimmerLinks( $Modem, @OutsideDimmers );
            printDimmerLinks( $Modem, @InsideDimmers );
            printDimmerLinks( $Modem, @SpecialRelay );
            printDimmerLinks( $Modem, @UnscheduledDimmers );

	    # add the X10 devices to the schedules last cuz they have no links
	    # and therefore cannot printDimmerLinks
            foreach $key ( keys %{ $iCfg->x10Ids() } ) {
                if ($DEBUG) {
                    print STDERR "StartupMonitor x10key=" . $key . "\n";
                }
                my $device = $Modem->getX10Dimmer( substr( $key, 0, 1 ),
                    substr( $key, 1 ) );
                my $allVars  = $iCfg->x10DevVars();
                my $schedule = $allVars->{ $key . "_schedule" };
                if ( defined($device) ) {

                    #attach a text lable to the device
                    my $lbl = $allVars->{ $key . "_label" };
                    if ( !defined($lbl) ) { $lbl = $key; }
                    $device->name($lbl);
                    if ( defined($schedule) ) {
                        my @scheduleParams = split( ' ', $schedule );
                        switch ( uc shift @scheduleParams ) {
                            case "OUTSIDE" {
                                push( @OutsideDimmers, $device );
                            }
                            case "INSIDE" {
                                push( @InsideDimmers, $device );
                            }
                            else {
                                print STDERR
"StartupMonitor encountered invalid x10 schedule "
                                  . $schedule . "\n";
                            }
                        }
                    }
                }
            }

            #note--Perl copies all the references to the new thread...
            #that is, futher changes on this thread will not be seen
            #on the create'd thread...so we don't touch $Modem anymore
            my @DimmerArray;

            push( @DimmerArray, $Modem );
            push( @DimmerArray, \@OutsideDimmers );
            push( @DimmerArray, \@InsideDimmers );
            push( @DimmerArray, \@SpecialRelay );
            push( @DimmerArray, $InsideEnable );
            push( @DimmerArray, $OutsideEnable );
            push( @DimmerArray, $SpecialEnable );
            push( @DimmerArray, \@Monitors );

            $bck = threads->create(
                'HomeAutomation::LightSchedule::backgroundThread',
                @DimmerArray );
            $bck->detach();
        }
    }
}

1;
