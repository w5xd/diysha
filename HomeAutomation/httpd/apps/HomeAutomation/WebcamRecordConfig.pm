#Copyright (c) 2014 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
#webcam alarm recording file format support 
use strict;
require Time::Piece;

package HomeAutomation::WebcamRecordConfig;

my %_webcams;

# the foscam FI9805W camera (and probably others) has an
# alarm recording function that can be configured to FTP a series
# of jpg snapshots when its built-in motion detection triggers.
# This configuration entry indicates how to calculate the date of
# the snapshot, and where the files are on disk on the apache server
# and what URL they appear on in our diysha website
   $_webcams{'1'} = { _location => '/home/webcamftp/wc3Upload/snap',
                        _urlBase => '../wc3Upload/',
                        _yearOff => 8,
			_yearLength => 15,
			_datePattern => "%Y%m%d-%H%M%S"};

   # these settings for a generic webcam whose manufacture won't claim credit
   $_webcams{'2'} = { _location => '/home/webcamftp/wc5Upload',
                      _urlBase => '../wc5Upload/',
                      _yearOff => 1,
                      _yearLength => 12,
                      _datePattern => "%y%m%d%H%M%S"};

# The $type agument is a key into _webcams, above.
sub new {
   my $class = shift;
   my $type = shift;
   my $self;
   my $lookup = $_webcams{$type};
   if (defined $lookup) {
   	$self = {};
        for (keys %$lookup) { $self->{ $_ } = $lookup->{$_}; }
        bless $self, $class;
   }
   return $self;
}

sub getLocation {
   my $self = shift;
   return $self->{_location};
}

# return a time/date object corresponding to the "time stamp"
# embedded in the file's name
sub getTime {
   my $self = shift;
   my $a2 = shift;
   my $tm = substr($a2, $self->{_yearOff}, $self->{_yearLength});
   my $t = Time::Piece->strptime($tm, $self->{_datePattern} );
   return $t;
}

sub urlBase {
	my $self = shift;
        return $self->{_urlBase};
}

1;
