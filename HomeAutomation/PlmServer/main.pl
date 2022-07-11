#!/usr/local/bin/perl -w -I./apps -I.
#
#Requires two command line arguments:
#  <port>  IP port number to listen on
#  <insteon log file name>

#note that the perl command line must have main's args after main.pl:
#perl -w -I./apps -I main.pl <port> <logfile>
#
#main.pl also requires a definition of the environment variable HTTPD_LOCAL_ROOT

use strict;
require HTTP::Daemon;
require IO::Select;
use HTTP::Status;
require HomeAutomation::StartMonitor;

my $ListenLimit = 3;
my $port;
my $insteonLogFile;

die "need port and insteon log file" if scalar @ARGV != 3;
$port           = $ARGV[0];
$insteonLogFile = $ARGV[1];
my $scheduleLogFile = $ARGV[2];

my %pagesLoaded;
opendir( my $dH, "web" )
  ;    #scan the directory...means you cannot add pages while running
while ( my $file = readdir($dH) ) {
    if ( $file =~ s/\.pm$// ) {
        eval "require web::$file";
        if ($@) {
            die "Cannot load web::$file\n$@";
        }
        else {
            my $loaded = "web::$file";
            $pagesLoaded{ "/" . $file } = $loaded;
        }
    }
}
closedir($dH);

HomeAutomation::StartMonitor::start($insteonLogFile, $scheduleLogFile);    #takes a while...

my $d = HTTP::Daemon->new(
    LocalAddr => 'localhost',
    LocalPort => $port,
    Listen    => $ListenLimit,
) || die;

print STDERR "My URL is: \"", $d->url, "\"\n";

my $selector = IO::Select->new($d);

for (;;) {
    if (my @ready = $selector->can_read ) {
    foreach my $fh (@ready) {
        if ( $fh == $d ) {
            # Create a new socket
            my $c = $d->accept;
            $selector->add($c);
        }
        else {
            # Process socket
            my $result = process_request( $fh, \%pagesLoaded );
            # Maybe we have finished with the socket
            if ( $result == 0 ) {
                $selector->remove($fh);
                $fh->close;
            }
        }
    }
}
}

print STDERR "main.pl exit\n";

sub process_request {
    my $c           = shift;    #connection to process
    my $pagesLoaded = shift;
    if ( my $r = $c->get_request ) {
        my $path = $r->uri->path;
        my $loaded = $pagesLoaded->{$path};
        print STDERR "main.pl process_request " . $path . "\n";
        if ( defined $loaded ) {
            $loaded->process_request( $c, $r );
        }
        else {
            $c->send_error(RC_NOT_FOUND);
        }
        return 1;
    }
    return 0;
}
