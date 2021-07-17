#!/usr/bin/perl

=pod

=head1 NAME

fx-loop.pl

=head1 SYNOPSIS

    fx-loop.pl --instrument=EUR_USD --max_quantity=50000 --increment=5000 [--loglevel=DEBUG]

=head1 DESCRIPTION

Open a trade in instrument when RSI 15minutes looks extreme.

Enter a positive quantity to enter a long trade, or a negative quantity to enter a short trade.

=cut


use strict;
use warnings;
$|=1;

use Finance::HostedTrader::Config;

use Finance::TA;
use Data::Dumper;
use List::Util qw(sum0 min max);
use Getopt::Long;
use Pod::Usage;
use Log::Log4perl;

my $options = {
    loglevel    =>  "INFO",
    instrument  => undef,
    max_quantity=> undef,
    increment   => undef,
    min_interval_between_trades => 3600,
    seconds_between_checks => 4,
    max_multiplier  => 3,
    min_multiplier  => 0.7,
};

GetOptions(
    $options,
    "help"      => sub { Getopt::Long::HelpMessage() },
    "loglevel=s",
    "instrument=s",
    "max_quantity=i",
    "increment=i",
    "min_interval_between_trades=i",
    "seconds_between_checks=i",
    "max_multiplier=f",
    "min_multiplier=f",
) or Getopt::Long::HelpMessage(2);

pod2usage(-exitval => 1, -verbose => 2) unless($options->{instrument} && $options->{max_quantity} && $options->{increment});

$options->{loglevel} = uc($options->{loglevel});
my $log_conf = qq(
log4perl rootLogger = $options->{loglevel}, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %m %n
);


Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();



my $oanda = Finance::HostedTrader::Config->new()->provider('oanda_demo');
$oanda->getAccountSummary(); ## This is only being called to check that the authentication token is valid.  if it's not, the program dies early.

my $instrument  = $options->{instrument};
my $timeframe   = 900;
my $numItems    = 100;
my $max_quantity= $options->{max_quantity};
my $increment   = $options->{increment};
my $min_interval_between_trades = $options->{min_interval_between_trades};

while(1) {

    sleep($options->{seconds_between_checks});

    my $dataset = $oanda->getHistoricalData($instrument, $timeframe, $numItems);
    my $candles = $dataset->{candles};

    my @close   = map { $_->{mid}{c} } @{ $candles };
    my @rsi_data = TA_RSI(0, $#close, \@close, 14);
    my $rsi = $rsi_data[2][$#{$rsi_data[2]}];

    my $latest_candle = $candles->[ $#{ $candles } ];

    $logger->info($latest_candle->{time}, "\t", $latest_candle->{mid}{c}, "\t", sprintf("%.2f", $rsi));

    if (has_signal_triggered($rsi, $max_quantity)) {
        $logger->info("RSI TRIGGER");
        my $instrument_trades = $oanda->getOpenTradesForInstrument($instrument);
        my $instrument_exposure = sum0 map { $_->{currentUnits} }  @$instrument_trades;
        $logger->info("Exposure = $instrument_exposure");

        if ($instrument_exposure > $max_quantity ) {
            $logger->info("Not opening further trades, max exposure reached");
            next;
        }

        $logger->info("Max Quantity = $max_quantity");
        $logger->info("Increment = $increment");
        my $min_trade_size = $oanda->getBaseUnitSize($instrument);
        $logger->debug("Provider minimum trade size = $min_trade_size");

        my $seconds_since_last_trade = seconds_since_last_opened_trade($instrument_trades);
        $logger->debug("Last trade was on " . $instrument_trades->[0]{openTime});
        $logger->debug("Seconds since last trade = $seconds_since_last_trade");

        if ($seconds_since_last_trade < $min_interval_between_trades) {
            $logger->info("Not opening further trades because one has been opened less than $min_interval_between_trades seconds ago");
            next;
        }

        my $multiplier;
        my @pivot_data = _get_indicator_atr14_min14_max14($instrument, 14400);

        if ($max_quantity > 0) { # long trade
            my $ask = $oanda->getAsk($instrument); # The price I can buy at
            $logger->info("Multiplier = (max14($pivot_data[2]) - ask($ask)) / atr14($pivot_data[0])");
            if ($pivot_data[2] > $ask) {
                $multiplier = ($pivot_data[2] - $ask ) / $pivot_data[0];
            } else {
                $multiplier = 0;
            }
        } else { # short trade
            my $bid = $oanda->getBid($instrument); # The price I can sell at
            $logger->info("Multiplier = (bid($bid) - min14($pivot_data[1])) / atr14($pivot_data[0])");
            if ($bid > $pivot_data[1]) {
                $multiplier = ($bid - $pivot_data[1]) / $pivot_data[0];
            } else {
                $multiplier = 0;
            }
        }
        $logger->info("Multiplier = $multiplier");


        $multiplier = $options->{max_multiplier} if ($multiplier > $options->{max_multiplier});
        my $adjusted_increment = int($increment * $multiplier / $min_trade_size) * $min_trade_size;
        $logger->info("Adjusted increment = $adjusted_increment");

        $logger->info("Skip multiplier < $options->{min_multiplier}") and next if ( $multiplier < $options->{min_multiplier});

        my $open_position_size = ($instrument_exposure + $adjusted_increment > $max_quantity ? $max_quantity - $instrument_exposure : $adjusted_increment );

        $logger->info("open market: $instrument $open_position_size");
        $oanda->openMarket($instrument, $open_position_size);
    }
}

sub _get_indicator_atr14_min14_max14 {
    my ($instrument, $timeframe) = @_;

    my $dataset = $oanda->getHistoricalData($instrument, $timeframe, 140);
    my $candles = $dataset->{candles};

    my @close   = map { $_->{mid}{c} } @{ $candles };
    my @high    = map { $_->{mid}{h} } @{ $candles };
    my @low     = map { $_->{mid}{l} } @{ $candles };


    my @atr_data = TA_ATR(0, $#close, \@high, \@low, \@close, 14);
    my $atr = $atr_data[2][ $#{$atr_data[2]} - 1 ];

    my @min_data = TA_MIN($#low-15, $#low, \@low, 14);
    my $min = $min_data[2][ $#{ $min_data[2]} ];

    my @max_data = TA_MAX($#high-15, $#high, \@high, 14);
    my $max = $max_data[2][ $#{ $max_data[2]} ];

    return ($atr, $min, $max);
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

sub seconds_since_last_opened_trade {
    my $trades = shift;
    my $most_recent_trade = $trades->[0];
    my $seconds_ago = time() - convertToEpoch($most_recent_trade->{openTime});

    return $seconds_ago;
}

sub convertToEpoch {
    my $datetime = shift;
    use DateTime::Format::RFC3339;

    my $parser = DateTime::Format::RFC3339->new();
    my $dt = $parser->parse_datetime($datetime);
    return $dt->epoch;
}
