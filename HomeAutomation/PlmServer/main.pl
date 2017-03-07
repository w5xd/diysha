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
use HTTP::Status;
require HomeAutomation::StartMonitor;

my $port;
my $insteonLogFile;

die "need port and insteon log file" if scalar @ARGV != 2;
$port = $ARGV[0];
$insteonLogFile = $ARGV[1];
HomeAutomation::StartMonitor::start($insteonLogFile); #takes a while...

my $d = HTTP::Daemon->new(
    LocalAddr => 'localhost',
    LocalPort => $port,
) || die;

my %webpages;
opendir( my $dH, "web" ); #scan the directory...means you cannot add pages while running
while ( my $file = readdir($dH) ) {
    if ( $file =~ s/\.pm$// ) {
        $webpages{ "/" . $file } = $file;
    }
}
closedir($dH);

my %pagesLoaded;

print "My URL is: \"", $d->url, "\"\n";

while ( my $c = $d->accept ) {
    while ( my $r = $c->get_request ) {
        my $path = $r->uri->path;
        print STDERR "path: $path\n";
        my $page = $webpages{$path};
       	my $loaded = $pagesLoaded{$path};
        if ( defined($page) && !defined( $pagesLoaded{$path} ) ) {
            eval "require web::$page";
            if ($@) {
		delete $webpages{$path};
                print STDERR "Cannot load web::$page\n$@";
            }
	    else {
	        $loaded = "web::$page";
                $pagesLoaded{$path} = $loaded;
            }
        }
        if ( defined $loaded ) {
            $loaded->process_request( $c, $r );
        }
        else {
            $c->send_error(RC_FORBIDDEN);
        }
    }
    $c->close;
    undef($c);
}
