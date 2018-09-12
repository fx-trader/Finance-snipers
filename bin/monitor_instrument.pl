#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: monitor_instrument.pl

use strict;
use warnings;
$|=1;

use Finance::HostedTrader::DataProvider::Oanda;
use Finance::TA;

my $instrument  = "USDCAD";
my $timeframe   = 900;

my $oanda = Finance::HostedTrader::DataProvider::Oanda->new();
my $data = $oanda->getHistoricalData($instrument, $timeframe, 200);

my $lastTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
my $lastTimeStampBlock  = int($lastTimeStamp / $timeframe);
my @dataset             = map { $_->{mid}{c} } @{ $data->{candles} };

$oanda->streamPriceData($instrument, sub {
        my $obj = shift;

        my $latest_price = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
        my $thisTimeStampBlock = int($obj->{time} / $timeframe);

        if ($lastTimeStampBlock == $thisTimeStampBlock) {
            $dataset[$#dataset] = $latest_price;
        } else {
            shift @dataset;
            push @dataset, $latest_price;
            $lastTimeStampBlock = $thisTimeStampBlock;
        }

        my @ret = TA_RSI(0, $#dataset, \@dataset, 14);
        print $lastTimeStampBlock, "\t", $ret[2][$#{$ret[2]}], "\n";
});
