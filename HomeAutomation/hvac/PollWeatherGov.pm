# perl class to call the forecast.weather.gov for lat/lon URL at first arg
# and parse the "current observations" temperature and time stamp to our stdout

require hvac::WeatherGov;
require IPC::Open2;

package hvac::PollWeatherGov;

use strict;

sub new {
    my $class = shift;
    my $self  = {
        _vars             => shift,
        _task             => hvac::WeatherGov->new(shift),
        _temperatureLabel => ""
    };
    bless $self, $class;
    return $self;
}

sub poll {
    my $self = shift;
    my $w    = $self->{_task};

    $w->acquireTemperature();
    my $wx    = $w->stringWeatherGov();
    my $label = $w->TemperatureLabel();
    return 0 if ( $label eq $self->{_temperatureLabel} );

    #only if label changes
    $self->{_temperatureLabel} = $label;
    my $exeFile = $ENV{HTTPD_LOCAL_ROOT} . "/../hvac/procWeatherGov";
    my ( $my_reader, $my_writer );
    my $pid = IPC::Open2::open2( $my_reader, $my_writer, $exeFile );
    $my_writer->autoflush(1);
    $my_reader->autoflush(1);
    print $my_writer "$wx\n";
    close $my_writer;
    my $lineout = <$my_reader>;
    close $my_reader;
    waitpid( $pid, 0);

    #append processed result to temperature file
    my @args = split( ' ', $lineout );    #convert tabs to spaces
    $lineout = "";
    foreach (@args) { $lineout .= $_ . ' '; }

    my $fn = $self->{_vars}->{FURNACE_LOG_LOCATION} . "/weather_gov.log";
    open( my $fh, ">>", $fn );
    print $fh $lineout . "\n";
    close $fh;

    return 1;
}

sub notifyTemperature {
    my $self = shift;
    my $who  = shift;
    my $w    = $self->{_task};
    return $who->temperatureEvent( $w->TemperatureF(), "WEATHERGOV" );
}

1;

