#!/usr/local/bin/perl

use strict;

if ($#ARGV != 0) {
	print STDERR "usage: extractLinks.pl <filename>\n";
	exit 1;
}

my $prevLine;
my $printing = 0;
my $printing2 = 0;

open (INSTLOG, $ARGV[0]);
while (<INSTLOG>) {
	chomp;
	my $lastOne = 0;
	if (!$printing){
	    if (index($_, "rintLinkTable") != -1) {
		print ("\n$prevLine\n");
	        $printing = 1;
		}
	} else {
	    $lastOne = 1 if (index($_, "end table") != -1) ;
	}
	if (!$printing2) {
		if (index($_, "Modem links") != -1) {
			$printing2 = 1;
			print "\n";
		}
        } else {
		$printing2 = 0 if ((length($_) < 30) || (length($_) > 35));
	}
	print "$_\n" if ($printing || $printing2);
	$prevLine = $_;
	$printing = 0 if ($lastOne);
}
close (INSTLOG);

exit 0;
