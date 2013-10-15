use lib "..";
use threads;
require HomeAutomation::LightSchedule;

#because of the PowerLineModule depending on w5xdInsteon.so,
#must add that file's directory to your LD_LIBRARY_PATH (Linux)
#or PATH (Windows) before this will run

	my @Dimmers = ( 0, 0, 0, 0 );
	my $bck = threads->create('HomeAutomation::LightSchedule::backgroundThread', @Dimmers);
	$bck->join();
1;
