#!/usr/bin/perl

use strict;
use warnings;

package main;
$|=1;

use Log::Log4perl;
use List::Util qw(sum0);

use Finance::HostedTrader::ExpressionParser;
use Finance::FXCM::Simple;

my $time_limit = time() + 1320; #Force a restart after 1320 seconds, to cleanup memory usage

# Initialize Logger
my $log_conf = q(
log4perl rootLogger = DEBUG, SCREEN
#log4perl rootLogger = DEBUG, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %m %n
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

my $symbol = $ENV{SYMBOL} || $logger->logdie("SYMBOL NOT DEFINED");          # The symbol to trade in
my $fxcm_symbol = $ENV{FXCM_SYMBOL} || $logger->logdie("FXCM_SYMBOL NOT DEFINED");    # Finance::FXCM::Simple only knows about FXCM symbols which have a different format than Finance::HostedTrader symbols
my $max_exposure = $ENV{MAX_EXPOSURE} || $logger->logdie("MAX_EXPOSURE NOT DEFINED");       # Maximum amount I'm willing to buy/sell in $symbol
my $exposure_increment = $ENV{EXPOSURE_INCREMENT} || $logger->logdie("EXPOSURE_INCREMENT NOT DEFINED");  # How much more do I want to buy each time
my $check_interval = 30;        # How many seconds to wait for before checking again if it's time to buy
my $direction = $ENV{DIRECTION} || $logger->logdie("DIRECTION NOT DEFINED");
$logger->logdie("DIRECTION has to be either 'long' or 'short'") unless ($direction eq 'long' or $direction eq 'short');

$logger->debug("Sniper reporting for duty");
$logger->debug("ACCOUNT ID = $ENV{FXCM_USERNAME} ($ENV{FXCM_ACCOUNT_TYPE})");
$logger->debug("SYMBOL = $symbol");
$logger->debug("INTERVAL = $check_interval seconds");

my $fxcm = Finance::FXCM::Simple->new($ENV{FXCM_USERNAME}, $ENV{FXCM_PASSWORD}, $ENV{FXCM_ACCOUNT_TYPE}, 'http://www.fxcorporate.com/Hosts.jsp');
while (1) {
    #last if ( -f "/tmp/snipers_disengage" );
    if (time() > $time_limit) {
        #$logger->debug("Exiting to allow memory cleanup");
        #last;
    }

    sleep($check_interval);

    $logger->debug("--------------------");

    my $bid = $fxcm->getBid($fxcm_symbol); # The price I can sell at
    my $ask = $fxcm->getAsk($fxcm_symbol); # The price I can buy at
    $logger->debug("BID = $bid");
    $logger->debug("ASK = $ask");
    my $spread = sprintf("%.5f", $ask - $bid);
    $logger->debug("SPREAD = $spread");

    # macd2_data not used at the moment, just call it here for the side effect of
    # macd value over 2hour timeframe being printed in the logs
    my $macd2_data = getIndicatorValue($symbol, '2hour', "macddiff(close, 12, 26, 9)");
    my $macd4_data = getIndicatorValue($symbol, '4hour', "macddiff(close, 12, 26, 9)");
    my $rsi_data = getIndicatorValue($symbol, '5min', "rsi(close,14)");
    my $ema_data = getIndicatorValue($symbol, '5min', "ema(close,200)");
    my $pivot_data = getIndicatorValue($symbol, '4hour', ($direction eq 'long' ? 'max' : 'min')."(close,14)");
    my $atr_data = getIndicatorValue($symbol, '4hour', "atr(14)");
    my $multiplier = ($pivot_data->[1] - $ask ) / $atr_data->[1]; #TODO hardcoded for long positions only

    my $symbol_trades = $fxcm->getTradesForSymbol($fxcm_symbol);
    my $symbol_exposure = sum0 map { $_->{size} }  @$symbol_trades;
    $logger->debug("$symbol exposure = $symbol_exposure");

    my @trades = sort { $b->{openDate} cmp $a->{openDate} } grep { $_->{direction} eq $direction } @{ $symbol_trades || [] };

    $logger->debug("Max Exposure = $max_exposure");
    $logger->debug("Increment = $exposure_increment");
    $logger->debug("Multiplier = $multiplier");

    if ($trades[0]) {
        my $most_recent_trade = $trades[0];
        my $seconds_ago = time() - convertToEpoch($most_recent_trade->{openDate});
        $logger->debug("LAST TRADE [$most_recent_trade->{openDate}, ${seconds_ago}s ago] = " . $most_recent_trade->{openPrice});
        my $latest_price = $fxcm->getAsk($fxcm_symbol);
        $logger->debug("Latest price = $latest_price");
        $logger->debug("Skip trade opened recently") and next if ($seconds_ago < 3600);
    }

    $logger->debug("Skip multiplier <1") if ( $multiplier < 1);

#    $logger->debug("Skip macd") and next if ($macd4_data->[1] >= 0);
    if ($direction eq 'long') {
        my $rsi_trigger = 35;
        $logger->debug("Set RSI trigger at $rsi_trigger");
        $logger->debug("Skip rsi") and next if ($rsi_data->[1] >= $rsi_trigger);
    } else {
        my $rsi_trigger = 65;
        $logger->debug("Set RSI trigger at $rsi_trigger");
        $logger->debug("Skip rsi") and next if ($rsi_data->[1] <= $rsi_trigger);
    }

    $logger->debug("Skip exposure") and next if ( $max_exposure < $symbol_exposure );

    my $open_position_size = ($symbol_exposure + $exposure_increment > $max_exposure ? $max_exposure - $symbol_exposure : $exposure_increment );
    $logger->debug("Add position to $symbol ($open_position_size)");
    $fxcm->openMarket($fxcm_symbol, HOSTED_TRADER_2_FXCM_DIRECTION($direction), $open_position_size);

    #$fxcm = undef; #This logouts from the FXCM session, and can take a few seconds to return
    zap( { subject => "fx-sniper: openmarket", message => "$fxcm_symbol\n$direction\nMULTIPLIER = $multiplier\n$open_position_size\n$ask\nRSI ($rsi_data->[0]) = $rsi_data->[1]\n" } );
}

$logger->debug("Sniper disengaged");

#unlink("/tmp/snipers_disengage");
exit(1);

# Trade direction can be long or short
# In FXCM, a long is represented by 'B' and a short by 'S'
# In HostedTrader, by 'long' and 'short'
# This function translates the hosted trader value to the fxcm value
sub HOSTED_TRADER_2_FXCM_DIRECTION {
    my $direction = shift;

    return 'B' if ($direction eq 'long');
    return 'S' if ($direction eq 'short');
    $logger->logconfess("Invalid direction value '$direction'");
}

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


# Post a request to zapier
sub zap {
    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $obj = shift;

    my $url = 'https://zapier.com/hooks/catch/782272/3f0nap/';

    my $ua      = LWP::UserAgent->new();
    my $response = $ua->post( $url, Content_Type => 'application/json', Content => encode_json($obj) );

    if ($response->is_success) {
        my $response_body = $response->as_string();
        $logger->debug($response_body);
        my $result = decode_json($response->content);
        if ($result->{status} && $result->{status} eq 'success') {
            $logger->info("Sent request to $url successfully");
        } else {
            $logger->error("Request to $url came back without success");
        }
    } else {
        $logger->error("Error sending request to $url");
        $logger->error($response->status_line());
    }
}

1;
