#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: bot.pl

use strict;
use warnings;
use MCE::Loop;
$|=1;

use Finance::HostedTrader::Config;
use Finance::TA;
use DateTime;
use DateTime::Format::RFC3339;
use Data::Dumper;


my $timeframe   = 900;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format('UNIX' );

my $max_requests_per_second = 2;

my @usd_denominated = grep /(^USD_|_USD$)/, $oanda->getInstruments();

MCE::Loop::init {
    chunk_size => 5, max_workers => scalar(@usd_denominated),
};

my %status = mce_loop {
    my ($mce, $chunk_ref, $chunk_id) = @_;

    my $instrument_names = join(',', @{$chunk_ref});
    my $sleep_interval = ($chunk_id - 1) * 4;
    sleep($sleep_interval);

    my $instruments;
    foreach my $instrument_name (@{$chunk_ref}) {
        #print "[$instrument_name][$$][$chunk_id] Fetch\n";
        $instruments->{$instrument_name}{data} = $oanda->getHistoricalData($instrument_name, $timeframe, 200);

        my $data = $instruments->{$instrument_name}{data};
        my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
        $instruments->{$instrument_name}{lastTimeStampBlock}  = int($thisTimeStamp / $timeframe);
        $instruments->{$instrument_name}{dataset}             = [ map { $_->{mid}{c} } @{ $data->{candles} } ];
    }

    while (1) {

        print "[$instrument_names][$$][$chunk_id] - START STREAM\n";

        my $http_response = $oanda->streamPriceData($chunk_ref, sub {
            my $obj = shift;
            my $print = 0;

            my $instrument_name = $obj->{instrument};

            my $thisPrice = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
            my $thisTimestamp = $obj->{time};
            my $thisTimeStampBlock = int($thisTimestamp / $timeframe);

            if ($instruments->{$instrument_name}{lastTimeStampBlock} == $thisTimeStampBlock) {
                $instruments->{$instrument_name}{dataset}[ $#{ $instruments->{$instrument_name}{dataset}} ] = $thisPrice
            } else {
                $print = 1;
                shift @{ $instruments->{$instrument_name}{dataset} };
                push @{ $instruments->{$instrument_name}{dataset} }, $thisPrice;
                $instruments->{$instrument_name}{lastTimeStampBlock} = $thisTimeStampBlock;
            }

            my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
            my $datetime_this_block = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimeStampBlock*$timeframe));
            my @ret = TA_RSI(0, $#{ $instruments->{$instrument_name}{dataset} }, $instruments->{$instrument_name}{dataset}, 14);
            my $rsi = $ret[2][$#{$ret[2]}];

            $print = ( $print ||  $rsi < 28 || $rsi > 72 );

            print "[$instrument_name][$$][$chunk_id] $datetime\t$thisPrice\t", sprintf("%.2f",$rsi), "\n" if ($print);

        });

        print "[$instrument_names][$$][$chunk_id] EXIT STREAM\t" . $http_response->status_line . "\t" . $http_response->decoded_content . "\n";
        sleep(3);

    }

} @usd_denominated;
