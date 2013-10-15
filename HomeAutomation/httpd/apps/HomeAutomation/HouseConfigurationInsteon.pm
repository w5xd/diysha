#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
package HomeAutomation::HouseConfigurationInsteon;

use strict;
use AppConfig;
my $DEBUG = 0;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {};
    my $iConfig = AppConfig->new(
        {
            CREATE => 1,
            CASE   => 1,
            GLOBAL => {
                ARGCOUNT => AppConfig::ARGCOUNT_ONE,
            },
        }
    );
    my $iCfgFileName =
      $ENV{HTTPD_LOCAL_ROOT} . "/../HouseConfiguration.ini";
    if ($DEBUG) {
    print STDERR "HouseConfigurationInsteon opening " . $iCfgFileName . "\n"; }
    $iConfig->file($iCfgFileName);
    $self->{_cfg} = $iConfig;
    bless ($self, $class);
    return $self;
}

sub insteonIds {   
    my $self = shift;
    my $iVars = $self->{_cfg};
    my %vars = $iVars->varlist( "^INSTEON_DEVID_", 1 );
    my %insteonIds = ();    #hash to be populated with empty hashes
    foreach my $key ( keys %vars ) {
        if (index( $key , "_") != -1)
        {
            my @keySplit = split( '_', $key, 2 );
            $insteonIds{ $keySplit[0] } = 0;
            if ($DEBUG) {
                print STDERR "getIds adding "
                  . $key
                  . " parsed is: "
                  . $keySplit[0] . "\n";
            }
	}
    }
    $self->{_insteonDevVars} = \%vars;
    $self->{_insteonIds} = \%insteonIds;
}

sub insteonDevVars { # must have called insteonIds first
    my $self =shift;
    return $self->{_insteonDevVars};
}

sub allVars {
    my $self = shift;
    if (!defined($self->{_allVars})) { 
        my %allVars = $self->{_cfg}->varlist(".*", 0);
	$self->{_allVars} = \%allVars;}
    return $self->{_allVars};
}

sub get {
    my $self = shift;
    return $self->{_cfg}->get(@_);
}

1;
