# perl class to call the furnace.cgi command on the modified Modtronix box
# and parse the temperatures

require IPC::Open2;

package hvac::PollModtronix;

use strict;

sub new {
    my $class = shift;
    my $self  = {
        _vars => shift,
    };
    bless $self, $class;
    return $self;
}

sub poll {
    my $self = shift;
    my $vars = $self->{_vars};

    my $cmd = $ENV{HTTPD_LOCAL_ROOT} . "/../hvac/curlFurnace" .
      " $vars->{FURNACE_IP} \"$vars->{FURNACE_LOGIN}\" |" . 
      " $ENV{HTTPD_LOCAL_ROOT}/../hvac/procFurnace -sp -sw";
    my ( $my_reader, $my_writer );
    my $pid = IPC::Open2::open2( $my_reader, $my_writer, $cmd );
    $my_writer->autoflush(1);
    $my_reader->autoflush(1);
    close $my_writer;
    my $lineout = <$my_reader>;
    close $my_reader;
    waitpid($pid, 0);
    #append processed result to temperature file
    my @args = split( ' ', $lineout );    #convert tabs to spaces
    $self->{_lastTemperature} = $args[2];
    $lineout = "";
    foreach (@args) { $lineout .= $_ . ' '; }
    my $fn = $self->{_vars}->{FURNACE_LOG_LOCATION}."/modtronix.log";
    open (my $fh, ">>", $fn);
    print $fh $lineout."\n";
    close $fh;
    return 1;
}

sub notifyTemperature {
    my $self = shift;
    my $who  = shift;  
    return $who->temperatureEvent( $self->{_lastTemperature}, "MODTRONIX" );
}

1;

