#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: monitor_instrument.pl

use strict;
use warnings;

$|=1;

use Finance::HostedTrader::Config;
use Finance::TA;
use DateTime;
use DateTime::Format::RFC3339;
use Data::Dumper;

my $instrument  = $ARGV[0] // "EUR_USD";
my $timeframe   = 10800;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
#$oanda->datetime_format('UNIX' );

my @instruments = $oanda->getInstruments();

my $http_response = $oanda->streamPriceData(\@instruments, sub {
        my $obj = shift;

        my $latest_price = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
        my $timestamp = $obj->{time};
        my $instrument = $obj->{instrument};

        print "$timestamp\t$instrument\t$latest_price\n";
});

warn "bye" . $http_response->status_line, $http_response->decoded_content;
