#!/usr/bin/perl

use strict;
use warnings;

$|=1;

use Log::Log4perl;
use LWP::UserAgent;
use JSON::MaybeXS;
use Data::Dumper;
use Redis;

my $log_conf = q(
log4perl rootLogger = DEBUG, SCREEN
#log4perl rootLogger = DEBUG, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern =[%p] %d{ISO8601} %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();



my $api_base = "http://api.fxhistoricaldata.com/v1";
#my $api_base = "http://172.17.0.1:5001";

#my $all_instruments = join(",", @{ get_all_instruments() });
my $all_instruments = "AUDUSD,AUDJPY,AUDNZD,CHFJPY,EURCAD,EURCHF,EURGBP,EURJPY,EURUSD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDUSD,NZDJPY,USDCAD,USDCHF,USDHKD,USDJPY,XAUUSD,XAGUSD,AUS200,ESP35,FRA40,GER30,HKG33,JPN225,NAS100,SPX500,UK100,UKOil,US30,USOil,USDOLLAR,Bund";
my @signals = (
    {   name => "trend_reverse",
        args => {
            expression  => "day(min(rsi(close,14),15)<35 and min(close,20) <= min(close,100)) and 4hour(crossoverup(ema(close,20),ema(close,200)))",
            start_period=> "4 hours ago",
#            instruments => join(",", @{ get_all_instruments() }),
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 7200,
        description => "",
    },
    {   name => "4hour RSI below 30 mad",
        args => {
            expression  => "rsi(close,14) < 30 and previous(rsi(close,14),1) < 30 and previous(rsi(close,14),2) < 30 and previous(rsi(close,14), 3) < 30",
            timeframe => "4hour",
            start_period=> "32 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 32400,
        description => "RSI gone mad",
    },
    {   name => "4hour RSI above 70 mad",
        args => {
            expression  => "rsi(close,14) > 70 and previous(rsi(close,14),1) > 70 and previous(rsi(close,14),2) > 70 and previous(rsi(close,14), 3) > 70",
            timeframe => "4hour",
            start_period=> "32 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 32400,
        description => "RSI gone mad",
    },
    {   name => "day ATR double average",
        args => {
            #expression  => "day(open > close and tr()>2*atr(14)) and 15minute(rsi(close,14)>60)",
            expression  => "tr()>2*atr(14)",
            timeframe => "day",
            start_period=> "4 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 7200,
        description => "Range double the average",
    },
    {   name => "GBPUSD buy",
        args => {
            expression  => "4hour(rsi(close,14) < 42) and 15minute(rsi(close,14) < 38)",
            start_period=> "2 hour ago",
            instruments => "GBPUSD",
        },
        signal_check_interval => 600,
        description => "Long GBPUSD weakness",
    },
    {   name => "trend reversal short",
        args => {
            expression  => "ema(close,21) < ema(close,200) and rsi(close, 14) > 60",
            timeframe => "4hour",
            start_period=> "32 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 32400,
        description => "Trend pullback",
    },
    {   name => "trend reversal long",
        args => {
            expression  => "ema(close,21) > ema(close,200) and rsi(close, 14) < 40",
            timeframe => "4hour",
            start_period=> "32 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 32400,
        description => "Trend pullback",
    },
#    {   name => "XAU buy",
#        args => {
#            expression  => "15minute(rsi(close,14) < 38)",
#            start_period=> "2 hour ago",
#            instruments => "XAUUSD",
#        },
#        signal_check_interval => 600,
#        description => "Short term XAU oversold",
#    },
    {   name => "Long pullback to support",
        args => {
            expression  => "min(low,5)%2B0.5*atr(14) > previous(max(close,50),50) and rsi(close,14)<38",
            timeframe   => "day",
            start_period=> "6 hour ago",
            max_loaded_items => 50000,
            instruments => $all_instruments,
        },
        signal_check_interval => 10200,
        description => "Retracement to support long",
    },
    {   name => "Short pushup to resistance",
        args => {
            expression  => "max(high,5)%2B0.5*atr(14) < previous(min(close,50),50) and rsi(close,14)>62",
            timeframe   => "day",
            start_period=> "6 hour ago",
            max_loaded_items => 50000,
            instruments => $all_instruments,
        },
        signal_check_interval => 10200,
        description => "Retracement to support short",
    },
    {   name => "Daily trade",
        args => {
            expression  => "rsi(close,14) < 40",
            timeframe   => "15min",
            start_period=> "1 hour ago",
            max_loaded_items => 50,
            instruments => "FRA40",
        },
        signal_check_interval => 300,
        description => "Daily trade check",
    },


);

my $redis = Redis->new( server => 'signal-scan-redis:6379' );
while (1) {
    foreach my $signal (@signals) {
        my $signal_name = $signal->{name};
        $logger->debug("$signal_name: begin");
        check_alert($signal);
        $logger->debug("$signal_name: end");
    }

    $logger->info("Sleeping");
    sleep(30);
}

## NOTE: These methods all take a $signal as an argument
## TODO: Refactor into a Signal class

# Checks if $signal has occured and sends an alert.
sub check_alert {
    my $signal = shift;
    my $signal_name = $signal->{name};

    return unless (_wants_alert($signal, $signal_name));
    return unless (_wants_signal_check($signal, $signal_name));

    my $args = $signal->{args};

    my $query_string = join("&", map { "$_=$args->{$_}" } keys(%$args));
    my $url = "$api_base/signals?$query_string";

    $logger->trace($url);

    my $result = get_endpoint_result($url);

    my $results = '';
    foreach my $instrument (sort keys %$result) {
        if (@{$result->{$instrument}->{data}}) {
            $results .= "$instrument\t$result->{$instrument}->{data}->[0]\n";
        }
    }
    $redis->hset("lastSignalCheck", $signal_name, time());

    if ($results) {
        $logger->info("$signal_name: TRIGGER ALERT $results");
        zap( { subject => "fx-signal-check: $signal_name", message => $results } );
        $redis->hset( "lastSignalAlert", $signal_name => time() );
    } else {
        $logger->debug("$signal_name: No trigger");
    }

    return $results;
}

# When a signal is triggered, we don't want to send the same alert multiple sequential times
# Hence a minimum trigger interval is set, and triggers won't fire unless X seconds have elapsed since the
# last trigger.
# Returns true if we want to send a trigger, or false if we don't want to send a trigger because one has already been sent and trigger_minimum_interval has not elapsed.
sub _wants_alert {
    my $signal = shift;
    my $signal_name = $signal->{name};

    my $lastSignalAlertTime = $redis->hget("lastSignalAlert", $signal_name);
    return 1 if (!$lastSignalAlertTime);
    my $trigger_minimum_interval = $signal->{trigger_minimum_interval} || 14400;
    my $triggered_seconds_ago = time() - $lastSignalAlertTime;

    $logger->debug("$signal_name: triggered $triggered_seconds_ago seconds ago, minimum_interval is $trigger_minimum_interval");
    return ( $triggered_seconds_ago >= $trigger_minimum_interval );
}

# Signal checking is a computationally expensive operation
# To minimize cost, we only compute a signal if at least X seconds have elapsed since the last computation
# Returns true if we want to compute a signal, or false if the signal has been computed and signal_check_interval has not elapsed.
sub _wants_signal_check {
    my $signal = shift;
    my $signal_name = $signal->{name};

    my $lastSignalCheckTime = $redis->hget("lastSignalCheck", $signal_name);
    return 1 if (!$lastSignalCheckTime);
    my $signal_interval = $signal->{signal_check_interval} || $logger->logdie("No interval defined for signal $signal_name");
    my $signal_check_in = $lastSignalCheckTime + $signal_interval - time();

    $logger->debug("$signal_name: due in $signal_check_in seconds");
    return ( $signal_check_in <= 0);
}
## END TODO REFACTOR INTO CLASS

sub get_all_instruments {
    return get_endpoint_result("$api_base/instruments");
}

sub get_endpoint_result {
    my $url = shift;

    my $ua = LWP::UserAgent->new();
    $logger->trace("Fetching $url");

    my $response = $ua->get( $url );
    die($!) unless($response->is_success);

    my $content = $response->content;
    my $d = decode_json($content);

    return $d->{results};
}

sub zap {
    my $obj = shift;

    my $url = 'https://zapier.com/hooks/catch/782272/3f0nap/';

    my $ua      = LWP::UserAgent->new();
    my $response = $ua->post( $url, Content_Type => 'application/json', Content => encode_json($obj) );

    if ($response->is_success) {
        my $response_body = $response->as_string();
        $logger->trace($response_body);
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
