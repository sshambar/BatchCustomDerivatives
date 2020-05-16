#!/usr/bin/env perl

my $name = "piwigo_deriv.pl";
my $version = 0.1;

=begin comment

Tool Name: piwigo_deriv.pl
Description: Queries list of or generates missing image derivatives and types
Author: Scott Shambarger
Author URI: http://github.com/sshambar/BatchCustomDerivatives

Example usage:

 # piwigo_deriv.pl -a gen_missing -c deriv.conf -t medium -s 0.5 -l 100

This tool can be used directly or as a background task (from cron)
to pre-generate missing image derivatives in a Piwigo gallery.
Authentication will be performed through the Piwigo WebService API, as
admin priviledges are required for most operations.

Username/password may be supplied as parameters, but the more secure
option is to supply these options in a config file (identified by -c option).

By default, all missing derivatives will be generated as quickly as possible.
However, generation may be restricted to specified types, and there are
options to control the speed and number of derivatives generated.


 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end comment
=cut

use strict;
use warnings;

use POSIX;
use JSON;
use LWP::UserAgent;
use Getopt::Long;

sub list_types($);
sub list_missing_derivs($);
sub gen_missing_derivs($);
sub get_types;
sub get_custom_types;
sub get_missing_derivs($$);
sub get_missing_custom_derivs($$);
sub get_missing_derivs_urls($$$);
sub error($);
sub json_query($;%);
sub get_ua;

my %opt = ();
Getopt::Long::Configure("bundling");
GetOptions(
    \%opt,
    qw/
          action|a=s
          base_url|b=s
          basic_auth|x
          config|c=s
          help|h
          limit|l=i
          password|p=s
          sleep|s=f
          timeout|o=i
          types|t=s
          username|u=s
          verbose|v:+
      /
);

my %conf_default = (
    action => '',
    base_url => 'http://localhost/piwigo',
    basic_auth => 0,
    limit => 0,
    password => '',
    sleep => 0,
    timeout => 20,
    types => '',
    username => 'admin',
    verbose => 0,
    );

my %conf = %conf_default;

# load config file
if (defined $opt{'config'}) {

    open CONFIG, "$opt{'config'}" or die "Couldn't open the config '$opt{'config'}'. $!\n";
    while (<CONFIG>) {
	chomp;
	s/^\s+|\s+$//g;
	next if /^#/;
	my ($key, $val) = m/^([^=\s]+)\s*=\s*"(.*)"$/;
	($key, $val) = m/^([^=\s]+)\s*=\s*(.*)$/ if ! defined($key);
	next if ! (defined($key) && defined($conf_default{$key}));
	$conf{$key} = $val;
    }
    close CONFIG;
}

# command line overrides
foreach my $conf_key (keys %conf_default) {
    $conf{$conf_key} = $opt{$conf_key} if defined $opt{$conf_key};
}
my $ws_url = $conf{base_url}.'/ws.php';

my $match = 0;
for (
    "list_types",
    "list_missing",
    "gen_missing",
    "list_custom_types",
    "list_missing_custom",
    "gen_missing_custom",
    "test_login",
    ) {
    $match = 1 if $_ eq $conf{action};
}
if ($conf{action} and $match == 0) {
    error "Unrecognized action: ".$conf{action};
}
undef $conf{types} if defined $conf{types} and $conf{types} eq 'all';

binmode STDOUT, ":encoding(utf-8)";

if ($conf{action} eq "" or defined ($opt{help})) {
    print "Piwigo Derivative Generator v".$version."\n";
    print "Usage: ".$name." -a <action> [ <options> ]\n";
    print "<options> may be:\n";
    print "  -a or --action=<one-of...>\n";
    print "    list_types - list valid derivative types\n";
    print "    list_missing - list urls of missing derivatives\n";
    print "    gen_missing - generate missing derivatives\n";
    print "    list_custom_types - list valid custom derivative types\n";
    print "    list_missing_custom - list urls of missing custom derivatives\n";
    print "    gen_missing_custom - generate missing custom derivatives\n";
    print "    test_login - test login, no other action\n";
    print "  -u or --username=<login> - login name (default: ".$conf_default{username}.")\n";
    print "  -p or --password=<pass> - login password (default: <empty>)\n";
    print "  -x or --basic_auth - use HTTP Basic Auth in photo query\n";
    print "  -s or --sleep=<secs> - seconds to sleep between requests (fractions ok)\n";
    print "  -l or --limit=<#> - max number of urls to process (default: <no-limit>)\n";
    print "  -b or --base_url=<url> - base url or site (default: ".$conf_default{base_url}.")\n";
    print "  -t or --types=<type>[,<type>] - derivative types to consider (default: <all>)\n";
    print "  -o or --timeout=<secs> - HTTP timeout (default: ".$conf_default{timeout}.")\n";
    print "  -c or --config=<config-file> - file containing option=value lines\n";
    print "Config file requires long option names (no dashes, # start comments)\n";
    exit(1);
}

# support single "." output when verbose
STDOUT->autoflush(1) if $conf{verbose} == 1;

my $ua = get_ua;

my %args = (
    username => $conf{username},
    password => $conf{password},
);
json_query "pwg.session.login", %args;
print "Cookies after login: ".$ua->cookie_jar->as_string."\n" if $conf{verbose} > 1;

for ($conf{action}) {
    /^list_types$/ && do { 
	list_types \&get_types;
    };
    /^list_missing$/ && do {
	list_missing_derivs \&get_missing_derivs;
    };
    /^gen_missing$/ && do {
	gen_missing_derivs \&get_missing_derivs;
    };
    /^list_custom_types$/ && do { 
	list_types \&get_custom_types;
    };
    /^list_missing_custom$/ && do {
	list_missing_derivs \&get_missing_custom_derivs;
    };
    /^gen_missing_custom$/ && do {
	gen_missing_derivs \&get_missing_custom_derivs;
    };
    /^test_login$/ && do {
	print "Login successful\n";
    };
}

json_query 'pwg.session.logout';

sub list_types($) {
    # type source function
    my $source = shift;

    my $types = &$source;
    my $str = join ",", @$types;
    print $str."\n";
}

sub list_missing_derivs($) {
    # url source function
    my $source = shift;

    my ($next, $urls);
    my $total = 0;
    do {
	$urls = &$source($conf{types}, $next);
	foreach (@$urls) {
	    print $_."\n";
	    $total++;
	    if ( $conf{limit} > 0 and $total >= $conf{limit} ) {
		undef $next;
		last;
	    }
	}
    } while($next);
}

sub gen_missing_derivs($) {
    # url source function
    my $source = shift;

    my ($next, $urls, $response);
    my $total = 0;
    my $failed = 0;
    my $sleep = 0;
    my $sleep_debt = 0.0;

    # url query agent
    my $cua = get_ua;
    if ($conf{basic_auth}) {
	$cua->default_headers->authorization_basic(
	    $conf{username},
	    $conf{password}
	    );
    }

    do {
	$urls = &$source($conf{types}, $next);
	foreach (@$urls) {
	    if ($sleep_debt > 1.0) {
		$sleep = floor($sleep_debt);
		$sleep_debt -= $sleep;
		sleep($sleep);
	    }
	    print "Generating derivatives:\n" if ($conf{verbose} and $total == 0);
	    print "." if $conf{verbose} == 1;
	    print $_."\n" if $conf{verbose} > 1;
	    $response = $cua->head($_);
	    if($response->is_error) {
		print STDERR "\nFailed: ".$_."\n";
		print STDERR "  error: ".$response->message."\n";
		# if we start with an error, bail
		exit if $total == 0;
		$failed++;
	    }
	    $total++;
	    $sleep_debt += $conf{sleep};
	    if ( $conf{limit} > 0 and $total >= $conf{limit} ) {
		undef $next;
		last;
	    }
	}
    } while($next);
    print "\n" if ($conf{verbose} == 1 and $total != 0);
    print "Total images processed: ".$total."\n"
	if ($conf{verbose} or $failed != 0);
    print "Total failures: ".$failed."\n" if $failed != 0;
}

sub get_types {
    my $result = json_query 'pwg.session.getStatus';
    return $result->{available_sizes};
}

sub get_custom_types {
    my $result = json_query 'bcd.getCustomDerivativeTypes';
    return $result->{types};
}

sub get_missing_derivs($$) {
    return get_missing_derivs_urls 'pwg.getMissingDerivatives',
	$_[0], $_[1];
}

sub get_missing_custom_derivs($$) {
    return get_missing_derivs_urls 'bcd.getMissingCustomDerivatives',
	$_[0], $_[1];
}

sub get_missing_derivs_urls($$$) {
    my $api = shift;
    my $stypes = shift;
    my $next = $_[0];

    my %xargs = ();

    if (defined $stypes) {
	my @types = split /,/, $stypes;
	$xargs{'types[]'} = \@types;
    }
    $xargs{prev_page} = $next if defined $next;
    my $result = json_query $api, %xargs;
    $_[0] = $result->{next_page};
    return $result->{urls};
}

sub error($) {
    print STDERR join(" ", @_)."\n";
    exit(1);
}

sub json_query($;%) {
    my ($method, %form) = @_;
    $form{method} = $method;
    my $response = $ua->post(
	$ws_url."?format=json",
	\%form
	);
    error "Method ".$method." failed to '".$conf{base_url}."': ".$response->message if $response->is_error;
    my %content;
    eval {
	%content = %{ JSON->new->utf8->decode($response->decoded_content) };
    };
    error "Method ".$method." returned invalid response" if not %content;
    error "Method ".$method." returned failure: ".$content{message} if $content{stat} ne "ok";
    error "Method ".$method." has no results" if not defined $content{result};
    return $content{result};
}

sub get_ua {
    return LWP::UserAgent->new(
	cookie_jar => {},
	agent => 'Mozilla/'.$name.' '.$version,
	timeout => $conf{timeout},
	);
}
