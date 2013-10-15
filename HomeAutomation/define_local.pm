#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md 
package define_local;

use AppConfig;
#take all the entries in the [BASH] section and copy them to the 
#environment.
sub SetEnvironmentVariables {
    my $fname = shift;
    my $config = AppConfig->new({
		    CREATE => 1,
		    CASE => 1,
		    GLOBAL => {
			    ARGCOUNT => AppConfig::ARGCOUNT_ONE,
		    },
	    });
    $config->file($fname);
    my %vars = $config->varlist("^BASH_", 1);
    my $key;
    my $value;
    while (($key, $value) = each(%vars)) {
	    $ENV{$key} = $value;
    }
}
1; # use'd files have to return true!
