#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::Config;
use strict;
use threads;
use threads::shared;
use AppConfig;

our $THERMOSTAT_IP :shared;
our $ROUTER_IP : shared;
our $FURNACE_IP : shared;
our $FURNACE_LOGIN : shared;

my $local_HEATPUMP_MIN_TEMPERATURE_F : shared ; 

my $DEBUG = 0;

# There is a problem with this design having to do with
# the fact that mod_perl instances a new interpreter when concurrent
# web requests are piling up. If our httpd/HomeAutomation/scheduleOnOff page
# gets run in a different interpreter instance than the original one that
# started httpd/apps/HomeAutomation/PollFurnace, then scheduleOnOff is not
# communicating with the thread that actually controls the HEATPUMP.
# (HEATPUMP_MIN_TEMPERATUR_F is the only exported here that also is
# changed by other web page calls--at least at this writing.)
# So instead in  $local_HEATPUMP_MIN_TEMPERATURE_F:shared, the value
# should be in something that is read/write access AND visible to
# all interpreters launched by mod_perl. Finding such a place is
# complicated by the fact that all modules that call here are
# supposed to call initialize() first, which is supposed to
# only read HouseConfiguration.ini once based on locking one
# of our :shared scalars. But that doesn't work because a whole new set
# of those shared scalars are instanced in every perl interpreter.

sub HEATPUMP_MIN_TEMPERATURE_F { 
    my $nv = shift;
    my $fname = $ENV{HTTPD_LOCAL_ROOT}."/run/HEATPUMP_MIN.txt";
    print STDERR "HEATPUMP_MIN_TEMPERATURE_F fname=$fname\n" if $DEBUG;
    if (defined($nv)) {
         if ($DEBUG) {
            print STDERR "HEATPUMP_MIN_TEMPERATURE_F setting changing from $local_HEATPUMP_MIN_TEMPERATURE_F\n";
            print STDERR "HEATPUMP_MIN_TEMPERATURE_F writing $nv\n";
         }
         $local_HEATPUMP_MIN_TEMPERATURE_F = $nv;
	 if (open (HPFILE, ">$fname"))	 {
		 print HPFILE $nv;
		 close (HPFILE);
	 }
    } else {
	    if (open (HPFILE, "<$fname"))   {
		while (<HPFILE>) { 
                    chomp; 
                    $local_HEATPUMP_MIN_TEMPERATURE_F = $_; 
                    print STDERR "HEATPUMP_MIN_TEMPERATURE_F read: $_\n" if $DEBUG;
		    last;
                }
		close (HPFILE);
	    }
    }
    return $local_HEATPUMP_MIN_TEMPERATURE_F;
}

sub initialize {
    lock($THERMOSTAT_IP);
    if (defined($THERMOSTAT_IP)) { return; }
    my $oneTimeFlag = shift;
    my $config = AppConfig->new({
	        CREATE => 1,
	        CASE => 1,
	        GLOBAL => {
		        ARGCOUNT => AppConfig::ARGCOUNT_ONE,
	        },
        });
    my $fname = $ENV{HTTPD_LOCAL_ROOT}."/../HouseConfiguration.ini";
    $config->file($fname);
    my %vars = $config->varlist("^BASH_", 1);
    $THERMOSTAT_IP  = $vars{THERMOSTAT_IP} ;
    $ROUTER_IP  = $vars{ROUTER_IP};
    $FURNACE_IP  = $vars{FURNACE_IP};
    $FURNACE_LOGIN  = $vars{FURNACE_LOGIN};
    $local_HEATPUMP_MIN_TEMPERATURE_F = $vars{HEATPUMP_MIN_TEMPERATURE_F}; 
    &HEATPUMP_MIN_TEMPERATURE_F($local_HEATPUMP_MIN_TEMPERATURE_F) if ($oneTimeFlag);
}

1;

