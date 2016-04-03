#!/usr/bin/perl

use strict;
use warnings;

package main;
$|=1;

use Log::Log4perl;
use List::Util qw(sum0);

use Finance::HostedTrader::ExpressionParser;
use Finance::FXCM::Simple;

# Initialize Logger
my $log_conf = q(
log4perl rootLogger = DEBUG, SCREEN
#log4perl rootLogger = DEBUG, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %m %n
#log4perl.appender.LOG1 = Log::Log4perl::Appender::File
#log4perl.appender.LOG1.filename = ./sniper.log
#log4perl.appender.LOG1.mode = append
#log4perl.appender.LOG1.layout = Log::Log4perl::Layout::PatternLayout
#log4perl.appender.LOG1.layout.ConversionPattern = %d{ISO8601} %p %M{2} %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();

$logger->logdie("FXCM_USERNAME NOT DEFINED") if (!$ENV{FXCM_USERNAME});
$logger->logdie("FXCM_PASSWORD NOT DEFINED") if (!$ENV{FXCM_PASSWORD});
$logger->logdie("FXCM_ACCOUNT_TYPE NOT DEFINED") if (!$ENV{FXCM_ACCOUNT_TYPE});

my $symbol = "AUDUSD";          # The symbol to trade in
my $fxcm_symbol = "AUD/USD";    # Finance::FXCM::Simple only knows about FXCM symbols which have a different format than Finance::HostedTrader symbols
my $max_exposure = 70000;       # Maximum amount I'm willing to buy/sell in $symbol
my $exposure_increment = 5000;  # How much more do I want to buy each time
my $check_interval = 30;        # How many seconds to wait for before checking again if it's time to buy
my $direction = "B";

$logger->debug("Sniper reporting for duty");
$logger->debug("Symbol = $symbol");
$logger->debug("Check Interval = $check_interval seconds");

while (1) {
    last if ( -f "/tmp/sniper_disengage" );

    sleep($check_interval);

    $logger->debug("--------------------");

    my $fxcm = Finance::FXCM::Simple->new($ENV{FXCM_USERNAME}, $ENV{FXCM_PASSWORD}, $ENV{FXCM_ACCOUNT_TYPE}, 'http://www.fxcorporate.com/Hosts.jsp');
    my $bid = $fxcm->getBid($fxcm_symbol); # The price I can sell at
    my $ask = $fxcm->getAsk($fxcm_symbol); # The price I can buy at
    $logger->debug("BID = $bid");
    $logger->debug("ASK = $ask");
    my $spread = sprintf("%.5f", $ask - $bid);
    $logger->debug("SPREAD = $spread");

    # Not actually using macd at the moment, just call it here for the side effect of
    # macd value being printed in the logs
    my $macd2_data = getIndicatorValue($symbol, '2hour', "macddiff(close, 12, 26, 9)");
    my $macd4_data = getIndicatorValue($symbol, '4hour', "macddiff(close, 12, 26, 9)");
    my $rsi_data = getIndicatorValue($symbol, '5min', "rsi(close,14)");

    my $symbol_trades = $fxcm->getTradesForSymbol($fxcm_symbol);
    my $symbol_exposure = sum0 map { $_->{direction} eq 'long' ? $_->{size} : $_->{size} * (-1) }  @$symbol_trades;
    $logger->debug("$symbol exposure = $symbol_exposure");

    my @trades = sort { $b->{openDate} cmp $a->{openDate} } grep { $_->{direction} eq 'long' } @{ $symbol_trades || [] };

    $logger->debug("Max Exposure = $max_exposure");
    $logger->debug("Current Exposure = $symbol_exposure");
    $logger->debug("Increment = $exposure_increment");

    if ($trades[0]) {
        my $most_recent_trade = $trades[0];
        my $seconds_ago = time() - convertToEpoch($most_recent_trade->{openDate});
        $logger->debug("LAST TRADE [$most_recent_trade->{openDate}, ${seconds_ago}s ago] = " . $most_recent_trade->{openPrice});
        my $latest_price = $fxcm->getAsk($fxcm_symbol);
        $logger->debug("Latest price = $latest_price");
        $logger->debug("Skip trade opened recently") and next if ($seconds_ago < 3600);
    }

#    $logger->debug("Skip macd") and next if ($macd4_data->[1] >= 0);
    my $rsi_trigger = ($macd4_data->[1] > 0 ? 38 : 32 );
    $logger->debug("Set RSI trigger at $rsi_trigger");
    $logger->debug("Skip rsi") and next if ($rsi_data->[1] >= $rsi_trigger);
    $logger->debug("Skip exposure") and next if ( $max_exposure < $symbol_exposure );

    my $open_position_size = ($symbol_exposure + $exposure_increment > $max_exposure ? $max_exposure - $symbol_exposure : $exposure_increment );
    $logger->debug("Add position to $symbol ($open_position_size)");
    $fxcm->openMarket($fxcm_symbol, $direction, $open_position_size);

    $fxcm = undef; #This logouts from the FXCM session, and can take a few seconds to return
}

$logger->debug("Sniper disengaged");

unlink("/tmp/sniper_disengage");

sub getIndicatorValue {
    my $symbol = shift;
    my $tf = shift;
    my $indicator = shift;

    my $signal_processor = Finance::HostedTrader::ExpressionParser->new(); # This object knows how to calculate technical indicators
    my $data = $signal_processor->getIndicatorData( {
            'fields'          => "datetime,$indicator",
            'symbol'          => $symbol,
            'tf'              => $tf,
            'maxLoadedItems'  => 50000,
            'numItems' => 1,
        });
    $signal_processor = undef;
    $logger->logdie("Failed to retrieve indicator '$indicator'") if (!$data || !$data->[0]);
    $logger->debug("$indicator [$data->[0]->[0]] ($tf) = $data->[0]->[1]");

    return $data->[0];
}

sub convertToEpoch {
    my $datetime = shift;
    use DateTime::Format::Strptime;

    my $parser = DateTime::Format::Strptime->new(pattern => "%Y-%m-%d %H:%M:%S", on_error=> "croak");
    my $dt = $parser->parse_datetime($datetime); 
    return $dt->epoch;
}

1;
