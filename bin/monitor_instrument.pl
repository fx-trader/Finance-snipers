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
my $timeframe   = $ARGV[1] // 900;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format("UNIX");

print "INSTRUMENT = $instrument\n";
print "TIMEFRAME = $timeframe\n";
my $data = $oanda->getHistoricalData($instrument, $timeframe, 200);

my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
my $lastTimeStampBlock  = int($thisTimeStamp / $timeframe);
my @close               = map { $_->{mid}{c} } @{ $data->{candles} };

my $print = 1;
my $http_response = $oanda->streamPriceData([$instrument], sub {
        use Term::ReadKey;
        ReadMode 4;
        my $key = ReadKey(-1);
        ReadMode 0;
        my $obj = shift;


        my $thisPrice = $obj->{closeoutBid} + (($obj->{closeoutAsk} - $obj->{closeoutBid}) / 2);
        #print "[DEBUG] $thisPrice\n";
        my $thisTimestamp = $obj->{time};
        my $thisTimeStampBlock = int($thisTimestamp / $timeframe);
        #print "[DEBUG] $thisTimeStampBlock $lastTimeStampBlock $thisTimestamp $timeframe\n";

        if ($lastTimeStampBlock == $thisTimeStampBlock) {
            $close[$#close] = $thisPrice;
        } else {
            $print = 1;
            shift @close;
            push @close, $thisPrice;
            $lastTimeStampBlock = $thisTimeStampBlock;
        }

        my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
        my $datetime_this_block = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimeStampBlock*$timeframe));
        my @rsi_data = TA_RSI(0, $#close, \@close, 14);
        my $rsi = $rsi_data[2][$#{$rsi_data[2]}];

        $print = (defined($key) || $print ||  $rsi < 28 || $rsi > 72 );

        #print "$datetime_this_block\t$datetime\t$thisPrice\t$rsi\n";
        if ($print) {

            my $atr_string = daily_atr_tr();

            my $dotIndex;

            while(1) {
                $dotIndex = index($thisPrice, ".");
                last if ($dotIndex > -1);
                $thisPrice .= ".0";
            }

            my $greyIndex = $dotIndex + 5;
            $thisPrice .= "0"x($greyIndex - length($thisPrice)) if ($greyIndex > length($thisPrice));
            print "$datetime\t",BOLD, RED, substr($thisPrice, 0, $greyIndex), GREY11, substr($thisPrice, $greyIndex), RESET,"\t", sprintf("%.2f",$rsi), "\t$atr_string\n";
        }
        $print = 0 if ($rsi > 28 && $rsi < 72);
});

sub daily_atr_tr {
    my $timeframe = 86400;
    my $data = 200;

    my $dataset = $oanda->getHistoricalData($instrument, $timeframe, $data);

    my @close   = map { $_->{mid}{c} } @{ $dataset->{candles} };
    my @high    = map { $_->{mid}{h} } @{ $dataset->{candles} };
    my @low     = map { $_->{mid}{l} } @{ $dataset->{candles} };

    my @atr_data = TA_ATR(0, $#close, \@high, \@low, \@close, 14);
    my $atr = $atr_data[2][ $#{$atr_data[2]} - 1 ];

    my @tr_data = TA_TRANGE($#close, $#close, \@high, \@low, \@close);
    my $tr      = $tr_data[2][$#{$tr_data[2]}];

    my $day_high = $high[$#high];
    my $day_low  = $low[$#low];



    return sprintf("ATR Yesterday = %.2f\tTR TODAY = %.3f ( $day_high - $day_low )\tRATIO=%.2f", $atr, $tr, $tr/$atr);
}
