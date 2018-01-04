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



my $api_base = "http://api.fxhistoricaldata.com";
#my $api_base = "http://172.17.0.1:5001";

#my $all_instruments = join(",", @{ get_all_instruments() });
my $all_instruments = "AUDUSD,AUDJPY,AUDNZD,CHFJPY,EURCAD,EURCHF,EURGBP,EURJPY,EURUSD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDUSD,NZDJPY,USDCAD,USDCHF,USDHKD,USDJPY,XAUUSD,XAGUSD,AUS200,ESP35,FRA40,GER30,HKG33,JPN225,NAS100,SPX500,UK100,UKOil,US30,USOil,USDOLLAR,Bund";
my @signals = (
    {   name => "4hour RSI below 30 mad - SHORT NOW !",
        args => {
            expression  => "4hour(previous(rsi(close,14),1) < 30 and previous(rsi(close,14),2) < 30 and previous(rsi(close,14), 3) < 30) and 15minute(rsi(close,14) > 65)",
            timeframe => "15min",
            start_period=> "2 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 900,
        description => "RSI gone mad",
        stop_loss => {
            expression => "max(high,2)",
            timeframe => "day",
        },
    },
    {   name => "4hour RSI above 70 mad - LONG NOW !",
        args => {
            expression  => "4hour(previous(rsi(close,14),1) > 70 and previous(rsi(close,14),2) > 70 and previous(rsi(close,14), 3) > 70) and 15minute(rsi(close,14) < 35)",
            timeframe => "15min",
            start_period=> "2 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        signal_check_interval => 900,
        description => "RSI gone mad",
        stop_loss => {
            expression => "min(low,2)",
            timeframe => "day",
        },
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
#    {   name => "This week long",
#        args => {
#            expression  => "rsi(close,14) < 34",
#            timeframe   => "15min",
#            start_period=> "2 hours ago",
#            max_loaded_items => 100,
#            instruments => "GBPJPY",
#        },
#        signal_check_interval => 300,
#        description => "",
#    },
#    {   name => "SHORT TERM LONG NOW!",
#        args => {
#            expression  => "rsi(close,14) < 44",
#            timeframe   => "15min",
#            start_period=> "2 hours ago",
#            max_loaded_items => 20,
#            instruments => "EURUSD",
#        },
#        signal_check_interval => 7200,
#        description => "",
#    },
    {   name => "Breakout EURGBP",
        args => {
            expression  => "high > 0.9030 or low < 0.831",
            timeframe   => "4hour",
            start_period=> "2 hours ago",
            max_loaded_items => 10,
            instruments => "EURGBP",
        },
        signal_check_interval => 7200,
        description => "",
    },
    {   name => "Big Breakout NZDJPY",
        args => {
            expression  => "high > 83.35",
            timeframe   => "4hour",
            start_period=> "2 hours ago",
            max_loaded_items => 10,
            instruments => "NZDJPY",
        },
        signal_check_interval => 7200,
        description => "",
    },
    {   name => "ENTER: Accumulate Long",
        args => {
            expression  => "15minute(rsi(close,14)<40) and 4hour(macddiff(close,12,26,9) < 0)",
            timeframe   => "15min",
            start_period=> "2 hours ago",
            max_loaded_items => 10000,
            instruments => "XAGUSD,XAUUSD",
        },
        signal_check_interval => 300,
        description => "",
    },
#    {   name => "CLOSE: Take Profit Long",
#        args => {
#            expression  => "15minute(rsi(close,14)>65) and 4hour(macddiff(close,12,26,9) < 0)",
#            timeframe   => "15min",
#            start_period=> "2 hours ago",
#            max_loaded_items => 10000,
#            instruments => "EURUSD,GBPJPY",
#        },
#        signal_check_interval => 300,
#        description => "",
#    },
    {   name => "ENTER: Accumulate Long",
        args => {
            expression  => "15minute(rsi(close,14)<35) and 4hour(macddiff(close,12,26,9) < 0)",
            timeframe   => "15min",
            start_period=> "2 hours ago",
            max_loaded_items => 10000,
            instruments => "EURCAD",
        },
        signal_check_interval => 300,
        description => "",
    },
#    {   name => "CLOSE: Take Profit Long",
#        args => {
#            expression  => "15minute(rsi(close,14)<35) and 4hour(macddiff(close,12,26,9) > 0)",
#            timeframe   => "15min",
#            start_period=> "2 hours ago",
#            max_loaded_items => 10000,
#            instruments => "EURCAD",
#        },
#        signal_check_interval => 300,
#        description => "",
#    },
    {   name => "ONE OFF: Long",
        args => {
            expression  => "15minute(rsi(close,14)<35)",
            timeframe   => "15min",
            start_period=> "2 hours ago",
            max_loaded_items => 10000,
            instruments => "GBPJPY,XAUUSD,XAGUSD",
        },
        signal_check_interval => 300,
        description => "",
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

    return unless (_wants_alert($signal));
    return unless (_wants_signal_check($signal));

    my $args = $signal->{args};

    my $query_string = join("&", map { "$_=$args->{$_}" } keys(%$args));
    my $url = "$api_base/signalsp?$query_string";

    $logger->trace($url);

    my $result;
    eval {
        $result = get_endpoint_result($url);
        1;
    } or do {
        $logger->error("$signal_name: $@");
        $redis->hset("lastSignalCheckError", $signal_name, time());
        return;
    };

    my $email_message_body = '';
    foreach my $instrument (sort keys %$result) {
        if (@{$result->{$instrument}->{data}}) {
            $email_message_body .= "$instrument\t$result->{$instrument}->{data}->[0]";
            if ( $signal->{stop_loss} ) {
                my $position_size_data = calculatePositionSize($instrument, 300, $signal->{stop_loss});
                my $entry   = $position_size_data->{current_price};
                my $exit    = $position_size_data->{exit};
                my $size    = $position_size_data->{size};

                $email_message_body .= "\t$entry\t$exit\t$size";
            }
            $email_message_body .= "\n";
        }
    }

    $redis->hset("lastSignalCheckSuccess", $signal_name, time());

    if ($email_message_body) {
        $logger->info("$signal_name: TRIGGER ALERT $email_message_body");
        zap( { subject => "fx-signal-check: $signal_name", message => "$email_message_body\n\n$url" } );
        $redis->hset( "lastSignalAlert", $signal_name => time() );
    } else {
        $logger->debug("$signal_name: No trigger");
    }

    return $email_message_body;
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

    my $lastSignalCheckTime = $redis->hget("lastSignalCheckSuccess", $signal_name);
    return 1 if (!$lastSignalCheckTime);
    my $lastSignalError = $redis->hget("lastSignalCheckError", $signal_name);
    $lastSignalError = 0 if (!$lastSignalError);

    my $timeSinceLastError = time() - $lastSignalError;
    if ( $timeSinceLastError < 60 ) {
        $logger->debug("signal_name: Error occurred $timeSinceLastError seconds ago, waiting for at least 60 seconds");
        return 0;
    }


    my $signal_interval = $signal->{signal_check_interval} || $logger->logdie("No interval defined for signal $signal_name");
    my $signal_check_in = $lastSignalCheckTime + $signal_interval - time();

    if ( $signal_check_in <= 0 ) {
        $logger->debug("$signal_name: check overdue by " . abs($signal_check_in) . " seconds");
        return 1;
    } else {
        $logger->debug("$signal_name: check due in $signal_check_in seconds");
        return 0;
    }
}
## END TODO REFACTOR INTO CLASS

sub get_all_instruments {
    return get_endpoint_result("$api_base/instruments");
}


#### The functions in this block deal with determing position size
sub getRatioCurrency {
    my ($instrument) = @_;

    use Finance::HostedTrader::Config;
    my $symbols = Finance::HostedTrader::Config->new()->symbols();
    my $symbolCurrency = $symbols->getSymbolDenominator($instrument);
    my $accountCurrency = 'GBP'; #TODO, hardcoded to GBP
    if ($symbolCurrency eq $accountCurrency) {
        return;
    }

    my $ratio_symbol = "${accountCurrency}${symbolCurrency}";
    return $ratio_symbol;
}

sub calculatePositionSize {
use POSIX;
    my ($instrument, $maxLoss, $stopLossData) = @_;

    my $exit_expression             = $stopLossData->{expression};
    my $exit_expression_timeframe   = $stopLossData->{timeframe};
    my $current_price   = get_endpoint_result_scalar("timeframe=5min&expression=close", $instrument);
    my $exit            = get_endpoint_result_scalar("timeframe=${exit_expression_timeframe}&expression=${exit_expression}", $instrument);

    my $ratioCurrency = getRatioCurrency($instrument);
    my $positionSize;
    if ($ratioCurrency) {
        use Finance::HostedTrader::Config;
        my $symbols = Finance::HostedTrader::Config->new()->symbols();
        my $ratio = get_endpoint_result_scalar("timeframe=5min&expression=close", $ratioCurrency);
        $positionSize = POSIX::floor( $maxLoss * $ratio / ($current_price - $exit) ) / $symbols->getSymbolMeta2($instrument);
    } else {
        $positionSize = POSIX::floor( $maxLoss / ($current_price - $exit) );
    }

    return {
        current_price   => $current_price,
        exit            => $exit,
        size            => $positionSize,
        maxLoss         => $maxLoss,
    };
}

#### END OF The functions in this block deal with determing position size

sub get_endpoint_result_scalar {
    my $parameters = shift;
    my $instrument = shift;

    my $result = get_endpoint_result("http://api.fxhistoricaldata.com/indicators?${parameters}&instruments=${instrument}");

    return $result->{$instrument}{data}[0][1];
}

sub get_endpoint_result {
    my $url = shift;

    my $ua = LWP::UserAgent->new();
    $logger->trace("Fetching $url");

    my $response = $ua->get( $url );
    $logger->logdie($!) unless($response->is_success);

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
