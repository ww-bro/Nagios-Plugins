#!/usr/bin/perl
############################################
# 					   #
# check_pilight.pl			   #
#					   #
# Author: Benedict Rosner		   #
# 	  <bro@wurzelwerk.it>		   #
#					   #
# Nagios Plugin to check pilight	   #
# http://pilight.org/			   #
#					   #
############################################
#
# Version 0.0.1
# - First working revision
#
# Version 0.0.2
# - Added Argument handling using Getopt::Long
# - eliminate global vars
# - Add perfdata support
# - Correct Nagios Output
#
# Version 0.0.3
# - Add Range support to -W and -C
# - add timeout option
# - deleted unnecessary verbose option
#
# ToDo:
# - add -c state to check for on/off
# - undef all vars in get_options()
#
## DEFINES
use strict;
use LWP;
use JSON;
use Getopt::Long;

## PRIVATE VARS
my $version = "0.0.3";

my $check = undef;
my $crit  = undef;
my $warn  = undef;
my $cond  = undef;
my $q_val = undef;
my $q_dev = undef;
my $url   = undef;
my $perf  = undef;
my $ret   = undef;
my $timeout = undef;

## MAIN
check_options();

if ($check eq 'name') {

	my $rval = get_value($q_dev,$q_val,make_request($url));

	if ($perf eq 1) {
	        $ret = $ret." | \'".$q_val."\'=".$rval.";".$warn.";".$crit;
        } else {
		$ret = undef;
	}

	$cond = check_value($rval, $crit);

	if ($cond eq 0) {
		undef($cond);
		$cond = check_value($rval, $warn);

		if ($cond eq 0) {
			$ret = "OK: ".$q_val." on ".$q_dev." : ".$rval.$ret;
			print $ret;
			exit 0;
		} else {
			$ret = "WARNING: ".$q_val." on ".$q_dev." : ".$rval.$ret;
			print $ret;
			exit 1;
		}
	} else {
		$ret = "CRITICAL: ".$q_val." on ".$q_dev." : ".$rval.$ret;
		print $ret;
		exit 2;
	}

} elsif ($check eq 'climate') {

	my $result = make_request($url);
	my $temp = get_value($q_dev,'temperature',$result);
	my $hum = get_value($q_dev,'humidity',$result);
	undef($result);

	my ($twarn, $hwarn) = split(',', $warn);
	my ($tcrit, $hcrit) = split(',', $crit);

	if ($perf eq 1) {
		$ret = " | \'temperature\'\=".$temp.";".$twarn.";".$tcrit."  \'humidity\'\=".$hum.";".$hwarn.";".$hcrit;
        } else {
		$ret = undef;
	}

	$cond = check_value($hum, $hcrit);

	if ($cond eq 0) {

		undef($cond);
		$cond = check_value($temp, $tcrit);

		if ($cond eq 0) {

			undef($cond);
			$cond = check_value($hum, $hwarn);
		
			if ($cond eq 0) { 

				undef($cond);
				$cond = check_value($temp, $twarn);

				if ($cond eq 0) {
					$ret = "OK: Temperature = ".$temp."°C, Humidity = ".$hum."%".$ret;
                        		print $ret;
	                        	exit 0;
				} else {
                                        $ret = "WARNING: Temperature = ".$temp."°C, Humidity = ".$hum."%".$ret;
                                        print $ret;
                                        exit 1;
				}
			} else {
			        my $ret = "WARNING: Humidity = ".$hum."%, Temperature = ".$temp."°C".$ret;
                                print $ret;
                                exit 1;
			}
		} else {
			my $ret = "CRITICAL: Temperature = ".$temp."°C, Humidity = ".$hum."%".$ret;
                        print $ret;
                        exit 2;
		}
	} else {
	        my $ret = "CRITICAL: Humidity = ".$hum."%, Temperature = ".$temp."°C".$ret;
                print $ret;
                exit 1;
	}
	undef($temp);
	undef($hum);
} else {
	print "ERROR: This should never happen\n";
	exit 3;
}

print "ERROR: This should never happen\n";
exit 3;

## SUBS

sub make_request {
	my $requsturl = shift(@_);
	my $ua = LWP::UserAgent->new;
	$ua->timeout("$timeout");
	$ua->env_proxy;
	my $response = $ua->get("$url");

	if ($response->is_success) {
		return from_json($response->decoded_content);
	} else {
		print "ERROR: Request failed: ".$response->status_line."\n";
		exit 3;
	};
}

sub get_value {
	my $dev = shift(@_);
	my $val = shift(@_);
	my $data = shift(@_);
	my $counter = 0;
	for my $item( @{$data} ){
        	if ( @{$data}["$counter"]->{'devices'}->[0] eq "$dev" ){
                	return @{$data}["$counter"]->{'values'}->{"$val"};
        	} else {
	                $counter = $counter+1;
        	        next;
	        };
		print "Error: Value not found";
		exit 3;
	};
}

sub check_value {

	my $value     = shift(@_);
	my $condition = shift(@_);

	my $alert     = undef;

	if ($condition =~ /^\d(\.\d\d)?$/) {
		# Outside of "0 - x"
		if (($value > $condition) and ($value < 0)){
			$alert = 1;
		} else {
			$alert = 0;
		}
	} elsif ($condition =~ /^\d(\.\d\d)?\:$/) {
		# Outside of "x - inf"
		if ($value < $condition) {
			$alert = 1;
		} else {
			$alert = 0;
		}
	} elsif ($condition =~ /^\~\:\d+(\.\d\d)?$/) {
		# Outside of "-inf - x"
		if ($value > $condition) {
			$alert = 1;
		} else {
			$alert = 0;
		}
	} elsif ($condition =~ /^\d+(\.\d\d)\:\d+(\.\d\d)$/) {
		# Outside the range of "x - y"
		my ($lower, $upper) = split(':', $condition);
		if (($value < $lower) or ($value > $upper)) {
			$alert = 1;
		} else {
			$alert = 0;
		}
	} elsif ($condition =~ /^\@\d+(\.\d\d)\:\d+(\.\d\d)$/) {
		# Inside the range of "x - y"
		my ($lower, $upper) = split(':', $condition);
		$lower .= s/\@//g;
		if (($value > $lower) or ($value < $upper)) {
			$alert = 1;
		} else {
			$alert = 0;
		}
	}

	if ($alert eq 1) {
		return 1;
	} else {
		return 0;
	}
}

sub check_options {

	my $o_version   = undef;
	my $o_help	= undef;

	my $o_host	= undef;
	my $o_port	= undef;
	my $o_timeout	= undef;
	my $o_device	= undef;
	my $o_check	= undef;
	my $o_name	= undef;
	my $o_warning	= undef;
	my $o_critical	= undef;
	my $o_perf	= undef;

        Getopt::Long::Configure ("bundling");
        GetOptions(
                'V'             => \$o_version,                 'version'                       => \$o_version,
                'h'             => \$o_help,                    'help'                          => \$o_help,

                'H:s'           => \$o_host,
                'P:s'           => \$o_port,
		'd:s'		=> \$o_device,
                'c:s'           => \$o_check,
                'n:s'           => \$o_name,
                'W:s'           => \$o_warning,
                'C:s'           => \$o_critical,
                't:s'           => \$o_timeout,
                'p'		=> \$o_perf,
        ) || unknown_arg();

	if (defined ($o_help)   ) { print_help();    exit 0;};
	if (defined ($o_version)) { print_version(); exit 0;};

	if (!defined ($o_host))	{ 
		print "ERROR: Host not defined (-H)\n";	
		exit 3;
	} elsif (!($o_host =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)){
		print "ERROR: Host \"".$o_host."\" is not an IP address.\n";
		exit 3;
	} else {
		if (defined ($o_port)) {
			if ($o_port =~ /^\d{1,6}$/){
				$url = "http://".$o_host.":".$o_port."/values";
			} else {
				print "ERROR: \"".$o_port."\" does not seem like a valid port.\n";
				exit 3;
			}
		} else {
			print "ERROR: Port not defined (-P)\n";
			exit 3;
		}
	}

	if (!defined($o_timeout)) {
		$timeout = 4;
	} elsif (!($o_timeout =~ /^\d{1,2}$/)) {
		print "ERROR: Timeout value does not seem valid.\n";
		exit 3;
	} else {
		$timeout = $o_timeout;
	}

	if (!defined ($o_device)) { 
		print "ERROR: Device not defined (-d)\n";	
		exit 3;
	} else {
		$q_dev = $o_device;
	}

	if (!defined($o_warning)){
		print "ERROR: Warning not defined (-W).\n";
		exit 3;
	} elsif (!defined($o_critical)){
		print "ERROR: Critical not defined (-C).\n";
		exit 3;
	} else {
		if ($o_check eq 'name') {
			if (!defined ($o_name) ){ 
				print "ERROR: You need to define a value name (-n) when using \"-c name\".\n"; 
				exit 3; 
			} else {
				if ($o_warning =~ /^((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?$/){
					if ($o_critical =~ /^((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?$/){
						$check = 'name';
						$q_val = $o_name;
						$warn = $o_warning;
						$crit = $o_critical;
					} else {
						print "ERROR: Critical must be in Nagios compatible format \(see -h\).\n";
						exit 3;
					}
				} else {
					print "ERROR: Warning must be in Nagios compatible format \(see -h\).\n";
					exit 3;
				}
			}
		} elsif ($o_check eq 'climate') {
			if (defined ($o_name) ){ 
				print "ERROR: Cannot use custom value name (-n) when checking \"-c climate\".\n"; 
				exit 3; 
			} else {
				if ($o_warning =~ /^((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?\,((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?$/){
					if ($o_critical =~ /^((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?\,((\~|(\@)?\d+(\.\d\d)?)?\:)?\d+(\.\d\d)?(\:)?$/){
						$check = 'climate';
						$warn = $o_warning;
						$crit = $o_critical;
					} else {
						print "ERROR: Critical must be in Nagios compatible format \(see -h\).\n";
						exit 3;
					}
				} else {
					print "ERROR: Warning must be in Nagios compatible format \(see -h\).\n";
					exit 3;
				}
			}
		} else {
			print "ERROR: Unknown check type or not defined. -c must be \"name\" or \"climate\".\n"; 
			exit 3;
		}
	}
	
	if (defined ($o_perf)) {
		$perf = 1;
	} else {
		$perf = 0;
	}
}

sub unknown_arg {
	print_info();
	print "Error: Unknown argument or option.\n";
	exit 3;
}

sub print_version {
        print $0." : Version ".$version."\n";
        exit 0;
}

sub print_info {
        print "\ncheck_pilight Nagios Plugin, version ".$version."\n";
        print "GNU/GPL, 2016 Benedict Rosner\n\n";
        print "$0  [-V|--version] [-h|--help] \n";
        print "           -H <Host> -P <Port> [-t <timeout>] -d <device> -c <name|climate>\n";
        print "           [-n <value name>] -W (<temp>,<hum>|<val>) -C (<temp>,<hum>|<val>)\n";
}


sub print_help {
        print_info();
        print <<EOT;

What it does:

-V, --version
   prints version number
-h, --help
   print this help message

-H <Host>
   Host to be checked (must be an IP address)
-P <Port>
   Port which pilight is running on
-t <timeout>
   http request timeout in s
-d <device>
   Name of the deivce in pilight config.json
-c <name|climate>
   Check type to be executed. Possible values are
      name: return custom value from <device> (needs -n)
      climate: returns Temparature and Humidity from <device>
-n <value name>
   Name of value to return. Needed in combination with "-c name"
-W [<temp>,<hum>|<val>]
   Warning threshold. Needs either a single value or two depending on check (-c)
-C [<temp>,<hum>|<val>]
   Critical threshold. Needs either a single value or two depending on check (-c)

   See https://nagios-plugins.org/doc/guidelines.html#AEN78 about defining Warning and Critical Ranges

EOT
}

## EOF ## 
