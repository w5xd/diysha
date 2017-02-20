#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::PollFurnace;
use strict;
use IPC::Open2;
use threads;
use threads::shared;
use AppConfig;

my $DEBUG = 1;

my $started : shared;

sub backgroundThread {
    my $dir = shift;    # hvac directory
    chdir $dir;
    my $houseConfig = AppConfig->new({
		    CREATE => 1,
		    CASE => 1,
		    GLOBAL => {
			    ARGCOUNT => AppConfig::ARGCOUNT_ONE,
		    },
	    });
    my $iCfgFileName =
    $ENV{HTTPD_LOCAL_ROOT} . "/../HouseConfiguration.ini";
    $houseConfig->file($iCfgFileName);
    my %houseconfigVars = $houseConfig->varlist("^BASH_", 1);
    my $hvacLogDir = $houseConfigVars{'FURNACE_LOG_LOCATION'};
    unlink $hvacLogDir.'/combine_inputs_err.txt',
      $hvacLogDir.'/procFurnace_err.txt',
      $hvacLogDir.'/check_set_eheat_out.txt';
    if ($DEBUG) {
        print STDERR "PollFurnace::backgroundThread at "
          . $dir
          . " and with temp "
          . $houseconfigVars{'HEATPUMP_MIN_TEMPERATURE_F'}
          . "\n and with login: "
          . $houseconfigVars{'FURNACE_LOGIN'}
	  . " and with log dir: "
	  . $houseconfigVars{'FURNACE_LOG_LOCATION'}
          . " and HTTPD_LOCAL_ROOT "
          . $ENV{HTTPD_LOCAL_ROOT} . "\n";
    }
#THIS code supports custom hvac monitor with a web server on it
#Its at FURNACE_IP nd has a set of web methods that return measured
#temperatures and furnace control line (O, B, R, G, Y, etc.) settings
#and changes (events). It also has a heat-pump override function
#on it that this code turns on and off based on measured temperatures 

    for ( my $pollCount = 0 ; $pollCount >= 0 ; ) {
        my $cmdInHandle;
        my $cmd = "";
        $cmd .= "export FURNACE_IP=\"$houseconfigVars{'FURNACE_IP'}\"";
        $cmd .=
          ";export FURNACE_LOGIN=\"$houseconfigVars{'FURNACE_LOGIN'}\"";
        $cmd .= ";./combine_inputs \"$houseconfigVars{'WEATHER_URL'}\" ";
        $cmd .=
          "2>>".$hvacLogDir."/combine_inputs_err.txt | ./procFurnace 2>>".
	   $hvacLogDir."/procFurnace_err.txt";
	if ($DEBUG) {
		print STDERR "PollFurnace command: \"". $cmd . "\n";
	}
        my $pid = open2( \*cmdResHandle, $cmdInHandle, 'bash', '-c', $cmd );
        my $lineOut;
        my $buf;
        while ( read( cmdResHandle, $buf, 60 * 57 ) ) { $lineOut .= $buf; }
        waitpid( $pid, 0 );

        if ( $lineOut != "" ) {
            my @args = split( ' ', $lineOut );    #convert tabs to spaces
            $lineOut = "";
            foreach (@args) { $lineOut .= $_ . ' '; }
            my $logf;
            open( $logf, ">>", $hvacLogDir."/temperature.log" );
            print $logf $lineOut . "\n";
            close($logf);

            $args[2] = '"' . $args[2] . '"';      #wrap parens
            unshift( @args,
                $houseconfigVars{'HEATPUMP_MIN_TEMPERATURE_F'} );
            unshift( @args, "./check_set_eheat" );
            $cmd = "";
            $cmd .= "export FURNACE_IP=\"$houseconfigVars{'FURNACE_IP'}\"";
            $cmd .=
";export FURNACE_LOGIN=\"$houseconfigVars{'FURNACE_LOGIN'}\";";
            foreach (@args) { $cmd .= $_ . ' '; }
            $cmd .= ">> ".$hvacLogDir."/check_set_eheat_out.txt 2>&1";
	    if ($DEBUG) {
		print STDERR "PollFurnace command: \"". $cmd . "\n";
	    }
            system "bash", "-c", $cmd;

            sleep 3 * 60;    # 3 minutes
        }
        else { sleep 15; }
    }
}

sub start {
    lock($started);
    print STDERR "PollFurnace::start started:$started\n" if $DEBUG;
    return if $started;
    $started = 1;
    my $bck = threads->create( 'HomeAutomation::PollFurnace::backgroundThread', @_ );
    $bck->detach();
}

1;

