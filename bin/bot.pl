#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: bot.pl

use strict;
use warnings;
$|=1;

use Finance::HostedTrader::Config;

use Finance::TA;
use DateTime;
use DateTime::Format::RFC3339;
use Data::Dumper;
use Log::Log4perl;
use MCE;
use MCE::Queue;


my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
#log4perl rootLogger = INFO, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
#log4perl.appender.SCREEN.layout.ConversionPattern = %m %n
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %x %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();


my @timeframes   = qw/60 900/;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format('UNIX' );

my @instrument_names = $oanda->getInstruments();

my $instruments;
foreach my $instrument_name (@instrument_names) {
    Log::Log4perl::NDC->push($instrument_name);

    $logger->info("FETCH HISTORICAL DATA");

    foreach my $timeframe (@timeframes) {
        my $data = $oanda->getHistoricalData($instrument_name, $timeframe, 200);
        my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
        $instruments->{$instrument_name}{$timeframe}{lastTimeStampBlock}  = int($thisTimeStamp / $timeframe);
        $instruments->{$instrument_name}{$timeframe}{data} = [ map { $_->{mid}{c} } @{ $data->{candles} } ];
    }

    Log::Log4perl::NDC->pop();
}

while (1) {

    $logger->info("START STREAM");

    my $http_response = $oanda->streamPriceData(\@instrument_names, sub {
        my $obj = shift;

        my $instrument_name = $obj->{instrument};
        Log::Log4perl::NDC->push($instrument_name);

        rsi($instruments->{$instrument_name}, $obj, 900);
        my $rsi = $instruments->{$instrument_name}{900}{rsi};

        if (1 || $rsi > 70 || $rsi < 30) {
            my $datetime = $instruments->{$instrument_name}{900}{datetime};
            my $thisPrice = $instruments->{$instrument_name}{900}{thisPrice};
            $logger->info("$datetime\t$thisPrice\t", sprintf("%.2f",$rsi), "\t", sprintf("%.2f", $instruments->{$instrument_name}{60}{rsi}));
        }

        Log::Log4perl::NDC->pop();
    });

    $logger->info("EXIT STREAM\t" . $http_response->status_line . "\t" . $http_response->decoded_content);
    sleep(1);

}

sub rsi {
    my $instrument_info = shift;
    my $latest_tick = shift;
    my $timeframe = shift;

    my @timeframes = keys %{ $instrument_info };

    foreach my $timeframe (@timeframes) {
        my $thisPrice = $latest_tick->{closeoutBid} + (($latest_tick->{closeoutAsk} - $latest_tick->{closeoutBid}) / 2);
        my $thisTimestamp = $latest_tick->{time};
        my $thisTimeStampBlock = int($thisTimestamp / $timeframe);

        if ($instrument_info->{$timeframe}{lastTimeStampBlock} == $thisTimeStampBlock) {
            $instrument_info->{$timeframe}{data}[ $#{ $instrument_info->{$timeframe}{data}} ] = $thisPrice
        } else {
            shift @{ $instrument_info->{$timeframe}{data} };
            push @{ $instrument_info->{$timeframe}{data} }, $thisPrice;
            $instrument_info->{$timeframe}{lastTimeStampBlock} = $thisTimeStampBlock;
        }

        my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
        my $datetime_this_block = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimeStampBlock*$timeframe));
        my @ret = TA_RSI(0, $#{ $instrument_info->{$timeframe}{data} }, $instrument_info->{$timeframe}{data}, 14);
        my $rsi = $ret[2][$#{$ret[2]}];
        $instrument_info->{$timeframe}{rsi} = $rsi;
        $instrument_info->{$timeframe}{thisPrice} = $thisPrice;
        $instrument_info->{$timeframe}{datetime} = $datetime;
    }
}
