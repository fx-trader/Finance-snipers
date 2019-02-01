#!/usr/bin/perl

use strict;
use warnings;

package main;
$|=1;

use Log::Log4perl;
use List::Util qw(sum0);
use Data::Dumper;

use Finance::FXCM::Simple;
use Finance::HostedTrader::Config;

my $cfg = Finance::HostedTrader::Config->new;

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

my $instrument = $ENV{INSTRUMENT} || $logger->logdie("INSTRUMENT NOT DEFINED");          # The instrument to trade in
my $max_exposure = $ENV{MAX_EXPOSURE} || $logger->logdie("MAX_EXPOSURE NOT DEFINED");       # Maximum amount I'm willing to buy/sell in $instrument
my $exposure_increment = $ENV{EXPOSURE_INCREMENT} || $logger->logdie("EXPOSURE_INCREMENT NOT DEFINED");  # How much more do I want to buy each time
my $check_interval = 120;        # How many seconds to wait for before checking again if it's time to buy
my $direction = $ENV{DIRECTION} || $logger->logdie("DIRECTION NOT DEFINED");
$logger->logdie("DIRECTION has to be either 'long' or 'short'") unless ($direction eq 'long' or $direction eq 'short');


{
    my $initial_delay = int(rand(10));
    $logger->info("Initial random delay of $initial_delay seconds");
    sleep($initial_delay);
}

#TODO $logger->info("ACCOUNT ID = $ENV{FXCM_USERNAME} ($ENV{FXCM_ACCOUNT_TYPE})");
$logger->info("INSTRUMENT = $instrument");
$logger->info("INTERVAL = $check_interval seconds");

while (1) {
    #last if ( -f "/tmp/snipers_disengage" );

    sleep($check_interval);

    $logger->info("--------------------");

    my $provider = $cfg->provider('oanda_demo');

    my $bid = $provider->getBid($instrument); # The price I can sell at
    my $ask = $provider->getAsk($instrument); # The price I can buy at
    $logger->info("BID = $bid");
    $logger->info("ASK = $ask");
    my $spread = sprintf("%.5f", $ask - $bid);
    $logger->info("SPREAD = $spread");

    my $instrument_trades = $provider->getOpenTradesForInstrument($instrument);
    my $instrument_exposure = sum0 map { $_->{currentUnits} }  @$instrument_trades;
    $logger->info("$instrument exposure = $instrument_exposure");

    $logger->info("Skip exposure") and next if ( $max_exposure <= $instrument_exposure );

    my @trades = sort { $b->{openTime} cmp $a->{openTime} } grep { ($direction eq 'long' ? $_->{currentUnits} > 0 : $_->{currentUnits} < 0) } @{ $instrument_trades || [] };

    $logger->info("Max Exposure = $max_exposure");
    $logger->info("Increment = $exposure_increment");
    my $min_trade_size = $provider->getBaseUnitSize($instrument);
    $logger->info("Min trade size = $min_trade_size");

    if ($trades[0]) {
        my $most_recent_trade = $trades[0];
        my $seconds_ago = time() - convertToEpoch($most_recent_trade->{openTime});
        $logger->info("LAST TRADE [$most_recent_trade->{openTime}, ${seconds_ago}s ago] = " . $most_recent_trade->{price});
        my $latest_price = $provider->getAsk($instrument);
        $logger->info("Latest price = $latest_price");
        $logger->info("Skip trade opened recently") and next if ($seconds_ago < 3600);
    }

    my $multiplier;
#    my $macd2_data = getIndicatorValue($instrument, '4hour', "macddiff(close, 12, 26, 9)");
    my $pivot_data = getIndicatorValue($instrument, '4hour', "atr(14), max(close,14), min(close,14)");
    my $rsi_data = getIndicatorValue($instrument, '15min', "rsi(close,14)");
    my $rsi_trigger = getRSITriggerValue($instrument, $direction);
    $logger->info("Set RSI trigger at $rsi_trigger");
    if ($direction eq 'long') {
        $logger->info("Multiplier = (max14($pivot_data->[2]) - ask($ask)) / atr14($pivot_data->[1])");
        if ($pivot_data->[2] > $ask) {
            $multiplier = ($pivot_data->[2] - $ask ) / $pivot_data->[1];
        } else {
            $multiplier = 0;
        }
        $logger->info("Multiplier = $multiplier");
        $logger->info("Skip rsi") and next if ($rsi_data->[1] >= $rsi_trigger);
#        $logger->info("Skip macd") and next if ($macd2_data->[1] >= 0);
    } else {
        $logger->info("Multiplier = (bid($bid) - min14($pivot_data->[3])) / atr14($pivot_data->[1])");
        if ($bid > $pivot_data->[3]) {
            $multiplier = ($bid - $pivot_data->[3]) / $pivot_data->[1];
        } else {
            $multiplier = 0;
        }
        $logger->info("Multiplier = $multiplier");
        $logger->info("Skip rsi") and next if ($rsi_data->[1] <= $rsi_trigger);
#        $logger->info("Skip macd") and next if ($macd2_data->[1] <= 0);
    }

    $multiplier = 3 if ($multiplier > 3);
    my $adjusted_exposure_increment = int($exposure_increment * $multiplier / $min_trade_size) * $min_trade_size;
    $logger->info("Adjusted incremental position size = $adjusted_exposure_increment");

    $logger->info("Skip multiplier < 0.7") and next if ( $multiplier < 0.7);

    my $open_position_size = ($instrument_exposure + $adjusted_exposure_increment > $max_exposure ? $max_exposure - $instrument_exposure : $adjusted_exposure_increment );
    $logger->info("Add position to $instrument ($open_position_size)");
    $provider->openMarket($instrument, HOSTED_TRADER_2_FXCM_DIRECTION($direction), $open_position_size);

    zap( { subject => "fx-sniper: openmarket", message => "$instrument\n$direction\nMULTIPLIER = $multiplier\nPOSITION SIZE = $open_position_size\nASK Price = $ask\nRSI ($rsi_data->[0]) = $rsi_data->[1]\n" } );
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
    my ($instrument, $direction) = @_;

    if ($direction eq 'long') {
        my $last_signal = getSignalValue($instrument, "15min", "rsi(close,14) < 30 and previous(rsi(close,14),1) < 30 and previous(rsi(close,14),2) < 30 and previous(rsi(close,14), 3) < 30");
        return 33 if (!$last_signal);
        my $seconds_ago = time() - convertToEpochWithStrptime($last_signal);
        $logger->info("rsi mad under 30 last seen $seconds_ago seconds ago");
        return ($seconds_ago < 12 * 60 * 60) ? 25 : 33; #12*60*60 = 12hours in seconds
    } elsif ($direction eq 'short') {
        my $last_signal = getSignalValue($instrument, "15min", "rsi(close,14) > 70 and previous(rsi(close,14),1) > 70 and previous(rsi(close,14),2) > 70 and previous(rsi(close,14), 3) > 70");
        return 67 if (!$last_signal);
        my $seconds_ago = time() - convertToEpochWithStrptime($last_signal);
        $logger->info("rsi mad over 70 last seen $seconds_ago seconds ago");
        return ($seconds_ago < 12 * 60 * 60) ? 75 : 67; #12*60*60 = 12hours in seconds
    } else {
        $logger->logconfess("Invalid value for direction parameter ('$direction')");
    }

}

sub getIndicatorValue {
    my $instrument = shift;
    my $tf = shift;
    my $indicator = shift;


    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $ua = LWP::UserAgent->new();
    my $url = "http://api.fxhistoricaldata.com/indicators?instruments=$instrument&expression=$indicator&item_count=1&timeframe=$tf";
    my $response = $ua->get($url);

    my $decoded_content = $response->decoded_content;

    if (!$response->is_success()) {
        $logger->logconfess("$url\n".$response->status_line."\n" . $decoded_content);
    }

    my $json_response = decode_json($decoded_content) || $logger->logconfess("Could not decode json response for $url\n$decoded_content");
    my $data = $json_response->{results}{$instrument}{data} || $logger->logconfess("json response for $url does not have expected structure\n$decoded_content");

    $logger->logconfess("Failed to retrieve indicator '$indicator'") if (!$data || !$data->[0]);
    foreach my $value (@{ $data->[0] }) {
        $logger->info("$indicator ($tf) = $value");
    }

    return $data->[0];
}

sub getSignalValue {
    my $instrument = shift;
    my $tf = shift;
    my $signal = shift;


    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $ua = LWP::UserAgent->new();
    my $url = "http://api.fxhistoricaldata.com/signals?instruments=$instrument&expression=$signal&item_count=1&timeframe=$tf";
    my $response = $ua->get($url);

    my $decoded_content = $response->decoded_content;

    if (!$response->is_success()) {
        $logger->logconfess("$url\n".$response->status_line."\n" . $decoded_content);
    }

    my $json_response = decode_json($decoded_content) || $logger->logconfess("Could not decode json response for $url\n$decoded_content");
    my $data = $json_response->{results}{$instrument}{data} || $logger->logconfess("json response for $url does not have expected structure\n$decoded_content");

    $logger->logconfess("Failed to retrieve indicator '$signal'") if (!$data);
    $logger->info("$signal ($tf) = " . (defined($data->[0]) ? $data->[0] : 'null'));

    return $data->[0] if (defined($data->[0]));
    return undef;
}

sub convertToEpoch {
    my $datetime = shift;
    use DateTime::Format::RFC3339;

    my $parser = DateTime::Format::RFC3339->new();
    my $dt = $parser->parse_datetime($datetime); 
    return $dt->epoch;
}

sub convertToEpochWithStrptime {
    my $datetime = shift;
    use DateTime::Format::Strptime;

    my $parser = DateTime::Format::Strptime->new(pattern => "%Y-%m-%d %H:%M:%S", on_error=> "croak");
    my $dt = $parser->parse_datetime($datetime);
    return $dt->epoch;
}



sub zap {
    use Email::Simple;
    use Email::Simple::Creator;
    use Email::Sender::Simple qw(sendmail);
    my $obj = shift;

    my $email = Email::Simple->create(
        header => [
            From => 'FX Robot <robot@fxhistoricaldata.com>',
            To => 'fxalerts@zonalivre.org',
            Subject => $obj->{subject},
        ],
        body => $obj->{message}
    );
    sendmail($email);
}

1;
