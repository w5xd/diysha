#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::PollFurnace;
use strict;
use IPC::Open2;
require HomeAutomation::Config;

my $DEBUG = 1;

sub backgroundThread {
    my $dir = shift;    # hvac directory
    chdir $dir;
    unlink 'combine_inputs_err.txt', 'procFurnace_err.txt',
      'check_set_eheat_out.txt';
    &HomeAutomation::Config::initialize(1);
        if ($DEBUG) {
              print STDERR "PollFurnace at " . $dir . " and with temp " .
                 &HomeAutomation::Config::HEATPUMP_MIN_TEMPERATURE_F() . 
                " and with login: " . $HomeAutomation::Config::FURNACE_LOGIN .
                " and HTTPD_LOCAL_ROOT " . $ENV{HTTPD_LOCAL_ROOT} .
		"\n";
        }
    return;
#THIS code supports custom hvac monitor with a web server on it
#Its at FURNACE_IP nd has a set of web methods that return measured
#temperatures and furnace control line (O, B, R, G, Y, etc.) settings
#and changes (events). It also has a heat-pump override function
#on it that this code turns on and off based on measured temperatures 
    for ( my $pollCount = 0 ; $pollCount >= 0 ; ) {
        my $cmdInHandle;
        my $cmd = "";
        $cmd .= "export FURNACE_IP=\"$HomeAutomation::Config::FURNACE_IP\"";
        $cmd .=
          ";export FURNACE_LOGIN=\"$HomeAutomation::Config::FURNACE_LOGIN\"";
        $cmd .= ";./combine_inputs \"$HomeAutomation::Config::WEATHER_URL\" ";
        $cmd .=
          "2>>combine_inputs_err.txt | ./procFurnace 2>>procFurnace_err.txt";
        my $pid = open2( \*cmdResHandle, $cmdInHandle, 'bash', '-c', $cmd );
        my $lineOut;
        my $buf;
        while ( read( cmdResHandle, $buf, 60 * 57 ) ) { $lineOut .= $buf; }
        waitpid( $pid, 0 );

        #      print STDERR "PollFurnace got " . $lineOut;
        if ( $lineOut != "" ) {
            my @args = split( ' ', $lineOut );    #convert tabs to spaces
            $lineOut = "";
            foreach (@args) { $lineOut .= $_ . ' '; }
            my $logf;
            open( $logf, ">>", "temperature.log" );
            print $logf $lineOut . "\n";
            close($logf);

            $args[2] = '"' . $args[2] . '"';      #wrap parens
            unshift( @args,
                &HomeAutomation::Config::HEATPUMP_MIN_TEMPERATURE_F() );
            unshift( @args, "./check_set_eheat" );
            $cmd = "";
            $cmd .= "export FURNACE_IP=\"$HomeAutomation::Config::FURNACE_IP\"";
            $cmd .=
";export FURNACE_LOGIN=\"$HomeAutomation::Config::FURNACE_LOGIN\";";
            foreach (@args) { $cmd .= $_ . ' '; }
            $cmd .= ">> check_set_eheat_out.txt 2>&1";
            system "bash", "-c", $cmd;

            #          print STDERR "PollFurnace command: ". $cmd . "\n";
            sleep 3 * 60;    # 3 minutes
        }
        else { sleep 15; }
    }
}

1;
