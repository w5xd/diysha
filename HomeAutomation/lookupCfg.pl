#!/usr/local/bin/perl
# call with 3 arguments: <config-file> <section-name> <value-name>
#Copyright (c) 2013 by Wayne Wright, Round Rock, Texas.
#See license at http://github.com/w5xd/diysha/blob/master/LICENSE.md
    use AppConfig;

    my $cfgFile = shift;
    my $section = shift;
    my $key = shift;
    #print STDERR "CFG=".$cfgFile." sec=".$section." key=".$key."\n";
    my $config = AppConfig->new({
		    CREATE => 1,
		    CASE => 1,
		    GLOBAL => {
			    ARGCOUNT => AppConfig::ARGCOUNT_ONE,
		    },
	    });
    $config->file($cfgFile);
    my %vars = $config->varlist("^". $section ."_", 1);
    my $ret = $vars{$key};
    print STDOUT $ret;
