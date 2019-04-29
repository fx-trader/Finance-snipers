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
use Term::ANSIColor qw(BOLD RED GREY11 RESET);

my $instrument  = $ARGV[0] // "EUR_USD";
my $timeframe   = 900;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format("UNIX");

my $data = $oanda->getHistoricalData($instrument, $timeframe, 200);

my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
my $lastTimeStampBlock  = int($thisTimeStamp / $timeframe);
my @dataset             = map { $_->{mid}{c} } @{ $data->{candles} };

my $first = 1;
my $http_response = $oanda->streamPriceData([$instrument], sub {
        my $obj = shift;
        my $print = 0;

        my $thisPrice = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
        my $thisTimestamp = $obj->{time};
        my $thisTimeStampBlock = int($thisTimestamp / $timeframe);

        if ($lastTimeStampBlock == $thisTimeStampBlock) {
            $dataset[$#dataset] = $thisPrice;
        } else {
            $print = 1;
            shift @dataset;
            push @dataset, $thisPrice;
            $lastTimeStampBlock = $thisTimeStampBlock;
        }

        my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
        my $datetime_this_block = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimeStampBlock*$timeframe));
        my @ret = TA_RSI(0, $#dataset, \@dataset, 14);
        my $rsi = $ret[2][$#{$ret[2]}];

        $print = ( $first || $print ||  $rsi < 28 || $rsi > 72 );
        $first = 0;

        #print "$datetime_this_block\t$datetime\t$thisPrice\t$rsi\n";
        if ($print) {
            my $dotIndex = index($thisPrice, ".") + 5;
            print "$datetime\t",BOLD, RED, substr($thisPrice, 0, $dotIndex), GREY11, substr($thisPrice, $dotIndex), RESET,"\t", sprintf("%.2f",$rsi), "\n";
        }
});
