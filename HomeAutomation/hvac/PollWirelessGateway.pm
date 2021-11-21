# perl class to poll the WirelessGateway node to retrieve
# any events from WirelessThermometers that it might have in
# its store-and-forward queue. Once retrieved, delete them
# from its queue.

package hvac::PollWirelessGateway;

use strict;

sub new {
    my $class = shift;
    my $self  = {
        _vars       => shift,
        _commPort   => shift,
        _timeOfPoll => time()
    };
    my %nodeList;
    foreach (@_) { $nodeList{$_} = 1; }
    $self->{_nodeList} =
      \%nodeList;    #remainder of arguments are nodes to check for eheat
    my $sendTest = shift;
    if ( !defined($sendTest) ) { $sendTest = 254; }
    $self->{_sendTest} = $sendTest;
    bless $self, $class;
    return $self;
}

sub poll {
    my $self = shift;
    my $log  = $self->{_vars}->{FURNACE_LOG_LOCATION};
    my $cmd =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../hvac/procWirelessGateway "
      . $self->{_commPort} . " GET";
    my $toDelete;
    my ( $my_reader, $my_writer );
    my $pid = IPC::Open2::open2( $my_reader, $my_writer, $cmd );
    $my_writer->autoflush(1);
    $my_reader->autoflush(1);
    close $my_writer;

    #format of stdout from procWirelessGateway looks like:
    #3 2017/02/26 21:13:27  65.62 262 -72 123
    #4 2017/02/26 21:14:11  71.92 283 -85 80
    #Found delete: 31
    while ( my $line = <$my_reader> ) {
        if ( $line =~ /^Found delete:\s/ ) {
            $toDelete = substr( $line, 14 );

            #if we see this line, don't read anymore
            #AND use it to send a DEL command back to the
            #WirelessGateway (below)
            last;
        }
        else {
            my @splitLine = split( ' ', $line );

            if ( scalar @splitLine > 0 ) {
                my $nodeId = shift @splitLine;

                if ( scalar @splitLine > 2 ) {
                    $line = "";
                    foreach (@splitLine) { $line .= $_ . ' '; }
                    if ( $splitLine[0] eq "HVAC" ) {
                        my $fnbase = "/HvacFurnace";
                        if ( $splitLine[1] =~ m/^Ti=/ ) {
                            $fnbase = "/HvacTemperature";
                        }
                        my $fn =
                            $self->{_vars}->{FURNACE_LOG_LOCATION}
                          . $fnbase
                          . $nodeId . ".log";
                        open( my $fh, ">>", $fn );
                        print $fh $line . "\n";
                        close $fh;
                        next;
                    }
                }

                if ( scalar @splitLine >= 6 ) {

                    #did INI file say this is an outside temperature?
                    my %recover = %{ $self->{_nodeList} };
                    if ( exists( $recover{$nodeId} ) ) {
                        $self->{_lastTemperature} = $splitLine[2];
                    }

                    #append processed result to temperature file
                    my $fn = $self->{_vars}->{FURNACE_LOG_LOCATION}
                      . "/wirelessThermometer$nodeId.log";
                    open( my $fh, ">>", $fn );
                    print $fh $line . "\n";
                    close $fh;
                    $self->{_timeOfPoll} = time();
                }
                elsif ( ( scalar @splitLine == 4 ) && $splitLine[0] eq "None" )
                {
                }
                else {
                    print STDERR "unprocessed line from Gateway: " . $line
                      . "\n";
                }
            }
        }
    }
    close $my_reader;
    waitpid( $pid, 0 );

    if ( defined $toDelete ) {
        my $cmd =
            $ENV{HTTPD_LOCAL_ROOT}
          . "/../hvac/procWirelessGateway "
          . $self->{_commPort}
          . " DEL $toDelete";
        system $cmd;
    }
    else {
        #if we have no events to delete for an hour, then
        #send a dummy message out
        my $now = time();
        if ( $now - $self->{_timeOfPoll} > 3600 ) {
            $self->{_timeOfPoll} = $now + rand 3600;    #fake future randomness
            my $cmd =
                $ENV{HTTPD_LOCAL_ROOT}
              . "/../hvac/procWirelessGateway "
              . $self->{_commPort}
              . " SENDTEST $self->{_sendTest}";
            print STDERR $cmd . "\n";
            system $cmd;
        }
    }

    return 1;
}

sub notifyTemperature {
    my $self = shift;
    my $who  = shift;
    return 0 if ( !defined( $self->{_lastTemperature} ) );
    return $who->temperatureEvent( $self->{_lastTemperature},
        "WIRELESSGATEWAY" );
}

1;

