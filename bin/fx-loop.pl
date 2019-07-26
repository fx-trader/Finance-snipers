#!/usr/bin/perl

use strict;
use warnings;
$|=1;

use Finance::HostedTrader::Config;

use Finance::TA;
use Data::Dumper;
use List::Util qw(sum0);
use Log::Log4perl;

my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
#log4perl rootLogger = INFO, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
#log4perl.appender.SCREEN.layout.ConversionPattern = %m %n
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();



my $oanda = Finance::HostedTrader::Config->new()->provider('oanda_demo');

my $instrument  = 'XAG_USD';
my $timeframe   = 900;
my $numItems    = 100;
my $quantity    = 50;

while(1) {
    my $dataset = $oanda->getHistoricalData($instrument, $timeframe, $numItems);
    my $candles = $dataset->{candles};

    my @close   = map { $_->{mid}{c} } @{ $candles };
    my @rsi_data = TA_RSI(0, $#close, \@close, 14);
    my $rsi = $rsi_data[2][$#{$rsi_data[2]}];

    my $latest_candle = $candles->[ $#{ $candles } ];

    $logger->info($latest_candle->{time}, "\t", $latest_candle->{mid}{c}, "\t", sprintf("%.2f", $rsi));

    if (has_signal_triggered($rsi, $quantity)) {
        $logger->info("RSI TRIGGER");
        my $instrument_trades = $oanda->getOpenTradesForInstrument($instrument);
        my $instrument_exposure = sum0 map { $_->{currentUnits} }  @$instrument_trades;
        $logger->info("Exposure = $instrument_exposure");

        if ($instrument_exposure == 0) {
            $logger->info("open market");
            $oanda->openMarket($instrument, $quantity);
        }
    }
    sleep(3);

}

sub has_signal_triggered {
    my ($rsi, $quantity) = @_;

    if ($quantity > 0 && $rsi < 27) {
        return 1;
    } elsif ($quantity < 0 && $rsi > 73) {
        return 1;
    }

    return 0;
}
