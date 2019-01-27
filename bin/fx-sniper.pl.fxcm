#!/usr/bin/perl

use strict;
use warnings;

package main;
$|=1;

use Log::Log4perl;
use List::Util qw(sum0);

use Finance::FXCM::Simple;

my $time_limit = time() + 1320; #Force a restart after 1320 seconds, to cleanup memory usage

# Initialize Logger
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

$logger->logdie("FXCM_USERNAME NOT DEFINED") if (!$ENV{FXCM_USERNAME});
$logger->logdie("FXCM_PASSWORD NOT DEFINED") if (!$ENV{FXCM_PASSWORD});
$logger->logdie("FXCM_ACCOUNT_TYPE NOT DEFINED") if (!$ENV{FXCM_ACCOUNT_TYPE});

my $symbol = $ENV{SYMBOL} || $logger->logdie("SYMBOL NOT DEFINED");          # The symbol to trade in
my $fxcm_symbol = $ENV{FXCM_SYMBOL} || $logger->logdie("FXCM_SYMBOL NOT DEFINED");    # Finance::FXCM::Simple only knows about FXCM symbols which have a different format than Finance::HostedTrader symbols
my $max_exposure = $ENV{MAX_EXPOSURE} || $logger->logdie("MAX_EXPOSURE NOT DEFINED");       # Maximum amount I'm willing to buy/sell in $symbol
my $exposure_increment = $ENV{EXPOSURE_INCREMENT} || $logger->logdie("EXPOSURE_INCREMENT NOT DEFINED");  # How much more do I want to buy each time
my $check_interval = 120;        # How many seconds to wait for before checking again if it's time to buy
my $direction = $ENV{DIRECTION} || $logger->logdie("DIRECTION NOT DEFINED");
$logger->logdie("DIRECTION has to be either 'long' or 'short'") unless ($direction eq 'long' or $direction eq 'short');


{
    my $initial_delay = int(rand(30));
    $logger->info("Initial random delay of $initial_delay seconds");
    sleep($initial_delay);
}

$logger->info("Sniper reporting for duty");
$logger->info("ACCOUNT ID = $ENV{FXCM_USERNAME} ($ENV{FXCM_ACCOUNT_TYPE})");
$logger->info("SYMBOL = $symbol");
$logger->info("INTERVAL = $check_interval seconds");

while (1) {
    #last if ( -f "/tmp/snipers_disengage" );
    if (time() > $time_limit) {
        $logger->info("Exiting to allow memory cleanup");
        last;
    }

    sleep($check_interval);

    $logger->info("--------------------");

    my $fxcm;
    eval {
        $fxcm = Finance::FXCM::Simple->new($ENV{FXCM_USERNAME}, $ENV{FXCM_PASSWORD}, $ENV{FXCM_ACCOUNT_TYPE}, 'http://www.fxcorporate.com/Hosts.jsp');
        1;
    } or $logger->logdie("Failed to login to fxcm account: $@");

    my $bid = $fxcm->getBid($fxcm_symbol); # The price I can sell at
    my $ask = $fxcm->getAsk($fxcm_symbol); # The price I can buy at
    $logger->info("BID = $bid");
    $logger->info("ASK = $ask");
    my $spread = sprintf("%.5f", $ask - $bid);
    $logger->info("SPREAD = $spread");

    my $symbol_trades = $fxcm->getTradesForSymbol($fxcm_symbol);
    my $symbol_exposure = sum0 map { $_->{size} }  @$symbol_trades;
    $logger->info("$symbol exposure = $symbol_exposure");

    $logger->info("Skip exposure") and next if ( $max_exposure <= $symbol_exposure );

    my @trades = sort { $b->{openDate} cmp $a->{openDate} } grep { $_->{direction} eq $direction } @{ $symbol_trades || [] };

    $logger->info("Max Exposure = $max_exposure");
    $logger->info("Increment = $exposure_increment");
    my $min_trade_size = $fxcm->getBaseUnitSize($fxcm_symbol);
    $logger->info("Min trade size = $min_trade_size");

    if ($trades[0]) {
        my $most_recent_trade = $trades[0];
        my $seconds_ago = time() - convertToEpoch($most_recent_trade->{openDate});
        $logger->info("LAST TRADE [$most_recent_trade->{openDate}, ${seconds_ago}s ago] = " . $most_recent_trade->{openPrice});
        my $latest_price = $fxcm->getAsk($fxcm_symbol);
        $logger->info("Latest price = $latest_price");
        $logger->info("Skip trade opened recently") and next if ($seconds_ago < 3600);
    }

    my $multiplier;
#    my $macd2_data = getIndicatorValue($symbol, '4hour', "macddiff(close, 12, 26, 9)");
    my $pivot_data = getIndicatorValue($symbol, '4hour', "atr(14), max(close,14), min(close,14)");
    my $rsi_data = getIndicatorValue($symbol, '15min', "rsi(close,14)");
    my $rsi_trigger = getRSITriggerValue($symbol, $direction);
    $logger->info("Set RSI trigger at $rsi_trigger");
    if ($direction eq 'long') {
        $multiplier = ($pivot_data->[2] - $ask ) / $pivot_data->[1];
        $logger->info("Multiplier = $multiplier");
        $logger->info("Skip rsi") and next if ($rsi_data->[1] >= $rsi_trigger);
#        $logger->info("Skip macd") and next if ($macd2_data->[1] >= 0);
    } else {
        $multiplier = ($bid - $pivot_data->[3]) / $pivot_data->[1];
        $logger->info("Multiplier = $multiplier");
        $logger->info("Skip rsi") and next if ($rsi_data->[1] <= $rsi_trigger);
#        $logger->info("Skip macd") and next if ($macd2_data->[1] <= 0);
    }

    $multiplier = 3 if ($multiplier > 3);
    my $adjusted_exposure_increment = int($exposure_increment * $multiplier / $min_trade_size) * $min_trade_size;
    $logger->info("Adjusted incremental position size = $adjusted_exposure_increment");

    $logger->info("Skip multiplier < 0.7") and next if ( $multiplier < 0.7);

    my $open_position_size = ($symbol_exposure + $adjusted_exposure_increment > $max_exposure ? $max_exposure - $symbol_exposure : $adjusted_exposure_increment );
    $logger->info("Add position to $symbol ($open_position_size)");
    $fxcm->openMarket($fxcm_symbol, HOSTED_TRADER_2_FXCM_DIRECTION($direction), $open_position_size);

    zap( { subject => "fx-sniper: openmarket", message => "$fxcm_symbol\n$direction\nMULTIPLIER = $multiplier\nPOSITION SIZE = $open_position_size\nASK Price = $ask\nRSI ($rsi_data->[0]) = $rsi_data->[1]\n" } );
    $fxcm = undef; #This logouts from the FXCM session, and can take a few seconds to return
}

$logger->info("Sniper disengaged");

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


sub getRSITriggerValue {
    my ($symbol, $direction) = @_;

    if ($direction eq 'long') {
        my $last_signal = getSignalValue($symbol, "15min", "rsi(close,14) < 30 and previous(rsi(close,14),1) < 30 and previous(rsi(close,14),2) < 30 and previous(rsi(close,14), 3) < 30");
        return 38 if (!$last_signal);
        my $seconds_ago = time() - convertToEpoch($last_signal);
        $logger->info("rsi mad under 30 last seen $seconds_ago seconds ago");
        return ($seconds_ago < 12 * 60 * 60) ? 30 : 38; #12*60*60 = 12hours in seconds
    } elsif ($direction eq 'short') {
        my $last_signal = getSignalValue($symbol, "15min", "rsi(close,14) > 70 and previous(rsi(close,14),1) > 70 and previous(rsi(close,14),2) > 70 and previous(rsi(close,14), 3) > 70");
        return 62 if (!$last_signal);
        my $seconds_ago = time() - convertToEpoch($last_signal);
        $logger->info("rsi mad over 70 last seen $seconds_ago seconds ago");
        return ($seconds_ago < 12 * 60 * 60) ? 70 : 62; #12*60*60 = 12hours in seconds
    } else {
        $logger->logconfess("Invalid value for direction parameter ('$direction')");
    }

}

sub getIndicatorValue {
    my $symbol = shift;
    my $tf = shift;
    my $indicator = shift;


    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $ua = LWP::UserAgent->new();
    my $url = "http://api.fxhistoricaldata.com/indicators?instruments=$symbol&expression=$indicator&item_count=1&timeframe=$tf";
    my $response = $ua->get($url);

    my $decoded_content = $response->decoded_content;

    if (!$response->is_success()) {
        $logger->logconfess("$url\n".$response->status_line."\n" . $decoded_content);
    }

    my $json_response = decode_json($decoded_content) || $logger->logconfess("Could not decode json response for $url\n$decoded_content");
    my $data = $json_response->{results}{$symbol}{data} || $logger->logconfess("json response for $url does not have expected structure\n$decoded_content");

    $logger->logconfess("Failed to retrieve indicator '$indicator'") if (!$data || !$data->[0]);
    foreach my $value (@{ $data->[0] }) {
        $logger->info("$indicator ($tf) = $value");
    }

    return $data->[0];
}

sub getSignalValue {
    my $symbol = shift;
    my $tf = shift;
    my $signal = shift;


    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $ua = LWP::UserAgent->new();
    my $url = "http://api.fxhistoricaldata.com/signals?instruments=$symbol&expression=$signal&item_count=1&timeframe=$tf";
    my $response = $ua->get($url);

    my $decoded_content = $response->decoded_content;

    if (!$response->is_success()) {
        $logger->logconfess("$url\n".$response->status_line."\n" . $decoded_content);
    }

    my $json_response = decode_json($decoded_content) || $logger->logconfess("Could not decode json response for $url\n$decoded_content");
    my $data = $json_response->{results}{$symbol}{data} || $logger->logconfess("json response for $url does not have expected structure\n$decoded_content");

    $logger->logconfess("Failed to retrieve indicator '$signal'") if (!$data);
    $logger->info("$signal ($tf) = " . (defined($data->[0]) ? $data->[0] : 'null'));

    return $data->[0] if (defined($data->[0]));
    return undef;
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
        $logger->info($response_body);
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
