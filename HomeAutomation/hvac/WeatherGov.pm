# perl class to call the forecast.weather.gov for lat/lon URL at first arg
# and parse the "current observations" temperature and time stamp to our stdout

package hvac::WeatherGov;

use strict;
require XML::Parser;
require LWP::Simple;    # used to fetch the URL

our @ISA = qw(XML::Parser);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( Handlers => {    # Creates our parser object
            Start   => \&handler::hdl_start, #handlers are outside this package
            End     => \&handler::hdl_end,
            Char    => \&handler::hdl_char,
            Default => \&handler::hdl_def,
        });
    
    #bizzare perl behavior is stuff I put on $self{} appears in the
    #handler callbacks, but modifications made by the handler callbacks
    #do not appear back in my methods afterwards. 
    #That is why _wxgov_state is used below.

    $self->{_url} = shift;
    bless $self, $class;
    return $self;
}

sub acquireTemperature {
    my $self  = shift;
    $self->{_level} = 0;
    $self->{_tags_seen} = [];
    delete $self->{_wxgov_error};
    # this is bizarre perl stuff
    my %wx; #make a hash
    $self->{_wxgov_state} = \%wx; #reference it
    #use that %wx has in the callbacks as $self 
    #is a different object in the callbacks than now.

    # list of XML tags we're looking for in order of nesting
    my $sp_forecast = LWP::Simple::get( $self->{_url} );

    if (defined($sp_forecast)) {
        #start calling (somebody) back...which is why we put pointer to our data into self
       eval {        $self->parse($sp_forecast); } ;
    } else {
        $self->{_wxgov_error} = "url fetch failed" unless defined $sp_forecast;
    }
}

sub printWeatherGov {
    my $self = shift;
    my $errmsg = $self->{_wxgov_error};
    die $errmsg if (defined($errmsg));

    my $wx = $self->{_wxgov_state};
    if ( !defined ($wx->{_timeLabel})) {
        print STDERR "getReportedTemp: No Time Label\n";
    }
    elsif ( !defined($wx->{_temperature}) ) {
        print STDERR "getReportedTemp: No Temperature\n";
    }
    else { print STDOUT $self->stringWeatherGov() . "\n"; }
}

sub stringWeatherGov {
    my $self = shift;
    my $wx = $self->{_wxgov_state};
    return $wx->{_temperature} . " Fahrenheit " . $wx->{_timeLabel} ;
}

sub TemperatureF
{
   my $self = shift;
   return $self->{_wxgov_state}->{_temperature};
}

sub TemperatureLabel 
{
   my $self = shift;
   return $self->{_wxgov_state}->{_timeLabel};
}

sub TemperatureError
{
	my $self = shift;
	return $self->{_wxgov_error};
}

package handler;

# The Handlers
sub hdl_start {
    my ( $self, $elt, %atts ) = @_;
    my $key;
    my $value;
    $self->{_level} += 1;
    push( @{$self->{_tags_seen}}, $elt );
}

sub hdl_def { }

#count the levels.
sub hdl_end {
    my ( $self, $elt ) = @_;
    $self->{_level}= $self->{_level} - 1;
    pop(@{$self->{_tags_seen}});
}

sub hdl_char {
    my $self = shift;
    my $str = shift;
    my @ar = @{$self->{_tags_seen}};
    my $wx = $self->{_wxgov_state};
    if ( ( $self->{_level} > 0 ) && ( $ar[0] eq "current_observation" ) ) {
        if ( $self->{_level} == 2 ) {
            if ( $ar[1] eq "temp_f" ) { $wx->{_temperature} = $str; }
            elsif ( $ar[1] eq "observation_time_rfc822" ) {
                $wx->{_timeLabel} = $str; 
            }
        }
    }
}

1;

