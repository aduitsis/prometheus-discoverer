#!/usr/bin/env perl

use v5.24;
use feature qw(postderef);
use File::Spec;
use FindBin qw($Bin);
use lib File::Spec->catdir($Bin,'local','lib','perl5');
use Getopt::Long;
use Data::Printer;
use IPv6::Address;
use IO::Socket::INET;
use Socket;
use YAML;
use Term::ANSIColor qw(:constants);
local $Term::ANSIColor::AUTORESET = 1;

GetOptions(
	'd'		=> \(my $DEBUG),
	'timeout|t'	=> \(my $timeout = 0.2),
	'f|file=s@'	=> \(my $files),
);

my @known_targets = ();
for my $file ($files->@*) {
	push @known_targets , map { ( $_->{ targets }->@* ) } YAML::LoadFile( $file )->@*
}

$DEBUG && say STDERR 'Found existing targets: '.join("\n",@known_targets);

#my $known = [ map { $_ =~ /^(?<host>.+?):(?<port>\d+)$/; { host => $+{host},port=>$+{port}  }  } @known_targets ];

my $known = { map { $_ => 0 } @known_targets };
$DEBUG && p $known;

my $result=[];

my @prefixes = @ARGV;

# see https://github.com/prometheus/prometheus/wiki/Default-port-allocations
my %ports = (
	'node'		=> 9100,
	'unbound'	=> 9167,
);

my %hosts = map { $_ => ( gethostbyaddr(inet_aton($_), AF_INET) // $_ ) } map { IPv4Subnet->new($_)->enumerate } @prefixes;
$DEBUG && p %hosts;

for my $exporter (sort keys %ports) {
	my $port = $ports{ $exporter };
	say STDERR YELLOW "$exporter (port $port)";
	for my $ip ( sort keys %hosts ) {
		my $sock = IO::Socket::INET->new(
			PeerAddr => $ip,
			PeerPort => $port,
			Proto => 'tcp',
			Timeout => $timeout
		);
		if( defined( $sock ) ) {
			if( $ip != $hosts{ $ip } ) {
				my $hostname = $hosts{ $ip };
				my $name = $hostname.':'.$port;
				$known->{ $name } = 1;
				say STDERR GREEN "\t".$name;
				push $result->@*,
					{ targets => [ $name ],
						labels	=> {
							instance => $hostname,
						},
				};
			}
			else {
				say STDERR "Cannot find PTR record for $ip";
				next
			}
		}
	}
}

for my $k (keys $known->%*) {
	if( $known->{ $k } != 1 ) {
		say STDERR RED "Warning! $k was present in previous files but was not found in this iteration. Will include it just to be on the safe side.";
		my ( $host, $port ) = ( $k =~ /^(?<host>.+?):(?<port>\d+)$/ );
		$host // die 'internal error! Host part cannot be undef';
		$port // die 'internal error! Port part cannot be undef';
		push $result->@*,
			{ targets => [ $k ],
				labels => {
					instance => $host,
				},
		};
	}
}

print YAML::Dump( $result )


