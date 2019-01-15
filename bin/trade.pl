#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: monitor_instrument.pl

use strict;
use warnings;
use MCE::Loop;
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
$oanda->datetime_format('UNIX' );

my @instruments = $oanda->getInstruments();

MCE::Loop::init {
    chunk_size => 50, max_workers => 2,
};

sub rsi {
    my ($oanda, $instrument, $timeframe, $period) = @_;

    my $data = $oanda->getHistoricalData($instrument, $timeframe, $period + 140);
    if (!$data->{candles}[$#{ $data->{candles} }]->{complete}) {
            pop @{ $data->{candles} };
    }
    my @dataset = map { $_->{mid}{c} } @{ $data->{candles} };
    my $timestamp = $data->{candles}[$#{ $data->{candles} }]{time};
    my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $timestamp));
    my @ret = TA_RSI(0, $#dataset, \@dataset, $period);

    return ( $datetime, sprintf("%.2f",$ret[2][$#{$ret[2]}]) );
}

my %status = mce_loop {
    my ($mce, $chunk_ref, $chunk_id) = @_;

    foreach my $instrument (@{ $chunk_ref }) {
        #print MCE->wid . " working on $instrument\n";
        my ($datetime, $rsi_3hour) = rsi($oanda, $instrument, 10800, 14);

        if ( $rsi_3hour >= 65 or $rsi_3hour <= 35) {
            my ($datetime_15min, $rsi_15min) = rsi($oanda, $instrument, 900, 14);
            MCE->gather($instrument, [ $datetime, $rsi_3hour, $rsi_15min]);
        }
    }

} @instruments;

my @sorted = sort { abs($status{$a}->[1] - 50) <=> abs($status{$b}->[1] - 50) } keys(%status);
foreach (@sorted) {
#print "$_\t$status{$_}->[1]\n";
print "$_\t", join("\t", @{ $status{$_} }), "\n";
}

exit;

my $data = $oanda->getHistoricalData($instrument, $timeframe, 200);

my $lastTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
my $lastTimeStampBlock  = int($lastTimeStamp / $timeframe);
my @dataset             = map { $_->{mid}{c} } @{ $data->{candles} };

my $http_response = $oanda->streamPriceData($instrument, sub {
        my $obj = shift;

        my $latest_price = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
        my $timestamp = $obj->{time};
        my $thisTimeStampBlock = int($timestamp / $timeframe);

        if ($lastTimeStampBlock == $thisTimeStampBlock) {
            $dataset[$#dataset] = $latest_price;
        } else {
            shift @dataset;
            push @dataset, $latest_price;
            $lastTimeStampBlock = $thisTimeStampBlock;
        }

        my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $timestamp));
        my @ret = TA_RSI(0, $#dataset, \@dataset, 14);
        print "$datetime\t$latest_price\t", sprintf("%.2f",$ret[2][$#{$ret[2]}]), "\n";
});
