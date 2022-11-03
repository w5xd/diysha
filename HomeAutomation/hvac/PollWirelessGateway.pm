# perl class to poll the WirelessGateway node to retrieve
# any events from WirelessThermometers that it might have in
# its store-and-forward queue. Once retrieved, delete them
# from its queue.

package hvac::PollWirelessGateway;

use strict;

my $FURNACE_Y2_MASK = 8;
my $FURNACE_Y_MASK = 16;
my $FURNACE_d_MASK = 1;
my $FURNACE_G_MASK = 2;
my $FURNACE_W_MASK = 4;
my $FURNACE_O_MASK = 32;

sub new {
    my $class = shift;
    my $self  = {
        _vars             => shift,
        _commPort         => shift,
        _timeOfPoll       => time(),    # first poll
	_lastTemperatures => [],
        _furnaceOnFlags   => {}
    };
    my %nodeList;
    foreach (@_) { $nodeList{$_} = 1; }
    $self->{_nodeList} =
      \%nodeList;    #remainder of arguments are nodes to check for eheat
    my $sendTest = shift;
    if ( !defined($sendTest) ) { $sendTest = 254; } #if aren't any eheat nodes
    $self->{_sendTest} = $sendTest;
    bless $self, $class;
    return $self;
}

sub furnaceTextToInt {
    my $hvo     = substr( shift, 4 );
    my $furnace = 0;

    my $idx = index($hvo, "Y2");
    if ($idx >= 0) {
	    $furnace += $FURNACE_Y2_MASK;
	    $hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 2);
    }
    $idx = index($hvo, "d");
    if ($idx >= 0) {
        $furnace += $FURNACE_d_MASK;
	$hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 1);
    }
    $idx = index($hvo, "G");
    if ($idx >= 0) {
        $furnace += $FURNACE_G_MASK;
	$hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 1);
    }
    $idx = index($hvo, "W");
    if ($idx >= 0) {
        $furnace += $FURNACE_W_MASK;
	$hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 1);
    }
    $idx = index($hvo, "Y");
    if ($idx >= 0) {
        $furnace += $FURNACE_Y_MASK;
	$hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 1);
    }
    $idx = index($hvo, "O");
    if ($idx >= 0) {
        $furnace += $FURNACE_O_MASK;
	$hvo = substr($hvo, 0, $idx) . substr($hvo, $idx + 1);
    }
    return $furnace;
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

#format of stdout from procWirelessGateway looks like (first column is packet node #)
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
                my $nodeId    = shift @splitLine;
                my %eheatList = %{ $self->{_nodeList} };
                if ( scalar @splitLine > 4 ) {
                    $line = "";
                    foreach (@splitLine) { $line .= $_ . ' '; }
                    if ( $splitLine[3] eq "HVAC" ) {
                        my $furnace   = 0;
                        my $furnaceIn = 0;
                        my $fnbase    = "/HvacFurnace";
                        if ( $splitLine[4] =~ m/^Ti:/ ) {
                            $fnbase       = "/HvacTemperature";
                            $line         = "";    #strip labels from numbers
                            $furnace = "";
                            $furnaceIn = "";
                            my $outside;
                            foreach (@splitLine) { 
                                       my $v = $_;
                                       if ($v =~ m/^To:/) { $outside = substr($v, 3); }
                                       if ($v =~ m/^T.:/) { $v = substr($v, 3); }
                                       $line .= $v . " ";
                            }
                            if ( defined($outside) && exists( $eheatList{$nodeId} ) ) {
				my $filterHoneywell = $self->{_filterHoneywell};
				if (!defined($filterHoneywell)) {
					$filterHoneywell = $outside;
				}
				$filterHoneywell *= 9;
				$filterHoneywell += $outside;
				$filterHoneywell /= 10;
				$self->{_filterHoneywell} = $filterHoneywell;
                                push @{$self->{_lastTemperatures}}, $filterHoneywell;
                                push @{$self->{_lastTemperatures}}, $nodeId;
                            }
                        }
                        elsif ( (scalar @splitLine > 5) && $splitLine[5] =~ m/^HVo=/ ) {
                            $furnace   = furnaceTextToInt( $splitLine[5] );
                            $furnaceIn = furnaceTextToInt( $splitLine[4] );
                            my $now = time();
                            $self->{_furnaceOnFlags}{$nodeId} =
                              [ $furnace, $now, $furnaceIn ]
                              ;    #save value for repetition
                        }
                        my $fn =
                            $self->{_vars}->{FURNACE_LOG_LOCATION}
                          . $fnbase
                          . $nodeId . ".log";
                        open( my $fh, ">>", $fn );
                        print $fh $line . " "
                          . $furnace . " "
                          . $furnaceIn . "\n";
                        close $fh;
                        next;
                    }
                }

                if ( scalar @splitLine >= 6 ) {

                    #did INI file say this is an outside temperature?
                    if ( exists( $eheatList{$nodeId} ) ) {
                        push @{$self->{_lastTemperatures}}, $splitLine[2];
                        push @{$self->{_lastTemperatures}}, $nodeId;
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

    #process _furnaceOnFlags. repeat previously acquired non-zero
    #furnace output so the plotter does something pretty with it
    my $furnaceOnFlags = $self->{_furnaceOnFlags};
    foreach ( keys %$furnaceOnFlags ) {
        my $nodeId = $_;
        my $entry  = $furnaceOnFlags->{$nodeId};
        my $now    = time();
        if ( ( $now - $entry->[1] ) < ( 5 * 60 ) ) { next; }
        my $furnace   = $entry->[0];
        my $furnaceIn = $entry->[2];
	my $keepgoing = $furnace & ~($FURNACE_O_MASK | $FURNACE_d_MASK);
        if ( $keepgoing > 0 ) {
            $self->{_furnaceOnFlags}{$nodeId} = [ $furnace, $now, $furnaceIn];
            my $fn =
                $self->{_vars}->{FURNACE_LOG_LOCATION}
              . "/HvacFurnace"
              . $nodeId . ".log";
            open( my $fh, ">>", $fn );
            (
                my $sec,  my $min,  my $hour, my $mday, my $mon,
                my $year, my $wday, my $yday, my $isdst
            ) = localtime();
            my $stamp = sprintf '%04d/%02d/%02d %02d:%02d:%02d', $year + 1900,
              $mon + 1, $mday, $hour, $min, $sec;
            print $fh $stamp
              . " 000 HVAC HVi=          HVo=          xxxxxxxxxxxxxxxxxxx  "
              . $furnace . " "
              . $furnaceIn . "\n";
            close $fh;
        }
    }

    return 1;
}

sub notifyTemperature {
    my $self             = shift;
    my $who              = shift;
    my $lastTemperatures = $self->{_lastTemperatures};
    $self->{_lastTemperatures} = [];
    return 0 if ( ( scalar @{$lastTemperatures} ) == 0 );
    my $ret;
    while ( scalar(@{$lastTemperatures}) != 0 ) {
        my $t    = shift @{$lastTemperatures};
        my $node = shift @{$lastTemperatures};
        $ret = $who->temperatureEvent( $t, "WIRELESSGATEWAY" . $node );
    }
    return $ret;
}

1;

