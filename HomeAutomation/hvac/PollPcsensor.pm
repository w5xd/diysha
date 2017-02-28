# perl class to call the pcsensor USB device

package hvac::PollPcsensor;

use strict;

sub new {
    my $class = shift;
    my $self = { _vars => shift, };
    bless $self, $class;
    return $self;
}

sub poll {
    my $self = shift;
    my $log  = $self->{_vars}->{FURNACE_LOG_LOCATION};
    my $cmd =
        $ENV{HTTPD_LOCAL_ROOT}
      . "/../pcsensor-0.0.2/pcsensor -f"   ;
    my ( $my_reader, $my_writer );
    my $pid = IPC::Open2::open2( $my_reader, $my_writer, $cmd );
    $my_writer->autoflush(1);
    $my_reader->autoflush(1);
    close $my_writer;
    my $lineout = <$my_reader>;
    close $my_reader;
    waitpid($pid, 0);
    if (defined $lineout) {
      #append processed result to temperature file
      my @args = split( ' ', $lineout );    #convert tabs to spaces
      $self->{_lastTemperature} = $args[4];
      $lineout = "";
      foreach (@args) { $lineout .= $_ . ' '; }
      my $fn = $self->{_vars}->{FURNACE_LOG_LOCATION}."/pcsensor.log";
      open (my $fh, ">>", $fn);
      print $fh $lineout."\n";
    }
    close $fh;
    return 1;
}

sub notifyTemperature {
    my $self = shift;
    my $who  = shift;  
    return $who->temperatureEvent( $self->{_lastTemperature}, "PCSENSOR" );
}

1;

