#!/usr/bin/perl

use strict;
use warnings;

$|=1;

use Log::Log4perl;
use LWP::UserAgent;
use JSON::MaybeXS;
use Data::Dumper;
use Redis;
use Memoize;
use Memoize::Expire;

my $log_level = uc($ENV{LOGLEVEL} // 'DEBUG');
my $log_conf = qq(
log4perl rootLogger = $log_level, SCREEN
#log4perl rootLogger = $log_level, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern =[%p] %d{ISO8601} %m %n
);

Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();



my $api_base = "http://api.fxhistoricaldata.com";
#my $api_base = "http://172.17.0.1:5001";


my $redis = Redis->new( server => 'signal-scan-redis:6379' );

#memoize("get_descriptive_statistics");
tie my %descriptive_stats_cache => 'Memoize::Expire', LIFETIME => 86400;
memoize("get_descriptive_statistics", SCALAR_CACHE => [ HASH => \%descriptive_stats_cache ] );

#tie my %all_instruments_cache => 'Memoize::Expire', LIFETIME => 604800;
#memoize("get_all_instruments", SCALAR_CACHE => [ HASH => \%all_instruments_cache ] );

tie my %screen_result_cache => 'Memoize::Expire', LIFETIME => 3600;
memoize("get_screen_result", SCALAR_CACHE => [ HASH => \%screen_result_cache ] );


while (1) {

    #my $all_instruments = join(",", @{ get_all_instruments() });
    my $all_instruments = "AU200_AUD,AUD_CAD,AUD_CHF,AUD_HKD,AUD_JPY,AUD_NZD,AUD_SGD,AUD_USD,BCO_USD,CAD_CHF,CAD_HKD,CAD_JPY,CAD_SGD,CHF_HKD,CHF_JPY,CHF_ZAR,CN50_USD,CORN_USD,DE10YB_EUR,DE30_EUR,EU50_EUR,EUR_AUD,EUR_CAD,EUR_CHF,EUR_CZK,EUR_DKK,EUR_GBP,EUR_HKD,EUR_HUF,EUR_JPY,EUR_NOK,EUR_NZD,EUR_PLN,EUR_SEK,EUR_SGD,EUR_TRY,EUR_USD,EUR_ZAR,FR40_EUR,GBP_AUD,GBP_CAD,GBP_CHF,GBP_HKD,GBP_JPY,GBP_NZD,GBP_PLN,GBP_SGD,GBP_USD,GBP_ZAR,HK33_HKD,HKD_JPY,IN50_USD,JP225_JPY,NAS100_USD,NATGAS_USD,NL25_EUR,NZD_CAD,NZD_CHF,NZD_HKD,NZD_JPY,NZD_SGD,NZD_USD,SG30_SGD,SGD_CHF,SGD_HKD,SGD_JPY,SOYBN_USD,SPX500_USD,SUGAR_USD,TRY_JPY,TWIX_USD,UK100_GBP,UK10YB_GBP,US2000_USD,US30_USD,USB02Y_USD,USB05Y_USD,USB10Y_USD,USB30Y_USD,USD_CAD,USD_CHF,USD_CNH,USD_CZK,USD_DKK,USD_HKD,USD_HUF,USD_INR,USD_JPY,USD_MXN,USD_NOK,USD_PLN,USD_SAR,USD_SEK,USD_SGD,USD_THB,USD_TRY,USD_ZAR,WHEAT_USD,WTICO_USD,XAG_AUD,XAG_CAD,XAG_CHF,XAG_EUR,XAG_GBP,XAG_HKD,XAG_JPY,XAG_NZD,XAG_SGD,XAG_USD,XAU_AUD,XAU_CAD,XAU_CHF,XAU_EUR,XAU_GBP,XAU_HKD,XAU_JPY,XAU_NZD,XAU_SGD,XAU_USD,XAU_XAG,XCU_USD,XPD_USD,XPT_USD,ZAR_JPY,NATGAS_SUGAR,USD_EUR,DE30_USD,CHF_EUR,GBP_EUR,JP225_USD,JPY_EUR";

    my ($long, $short) = get_screen_result();
    my ($long_instrument, $long_rsi_date, $long_rsi) = @$long;
    my ($short_instrument, $short_rsi_date, $short_rsi) = @$short;
    $long_instrument .= ",XCU_USD" unless $long_instrument eq 'XCU_USD';

    my @signals = (
#        {   name => "LONG NOW",
#            enabled => 0,
#            args => {
#                expression  => "rsi(close,14) < " . ($long_rsi - 33),
#                timeframe => "15min",
#                start_period=> "15 minutes ago",
#                instruments => $long_instrument,
#                item_count  => 1,
#            },
#            signal_check_interval => 60,
#            trigger_minimum_interval => 3600,
#            description => "",
#        },
#        {   name => "SHORT NOW",
#            enabled => 0,
#            args => {
#                expression  => "rsi(close,14) > " . ($short_rsi + 33),
#                timeframe => "15min",
#                start_period=> "15 minutes ago",
#                instruments => $short_instrument,
#                item_count  => 1,
#            },
#            signal_check_interval => 60,
#            trigger_minimum_interval => 3600,
#            description => "",
#        },
        {   name => "RSI extreme > 70",
            args => {
                expression  => "rsi(close,14) > 70",
                timeframe => "15min",
                start_period=> "2 hours ago",
                instruments => "$long_instrument,$short_instrument",
                item_count  => 1,
            },
            signal_check_interval => 60,
            description => "First we choose the instrument with highest and lowest daily RSI. This signal triggers when the 15min RSI is above 70 on said instruments.",
        },
        {   name => "RSI extreme < 30",
            args => {
                expression  => "rsi(close,14) < 30",
                timeframe => "15min",
                start_period=> "2 hours ago",
                instruments => "$long_instrument,$short_instrument",
                item_count  => 1,
            },
            signal_check_interval => 60,
            description => "First we choose the instrument with highest and lowest daily RSI. This signal triggers when the 15min RSI is below 70 on said instruments.",
        },
        {   name => "Weekly RSI extreme",
            args => {
                expression  => "rsi(close,14) < 22 or rsi(close,14) > 78",
                timeframe => "week",
                start_period=> "7 days ago",
                instruments => $all_instruments,
                item_count  => 1,
            },
            signal_check_interval => 86400,
            description => "weekly extreme, stay on the trend on pullbacks, but look for a long term reversal in the next 6 to 12 months.  Look at USOil Jan 2015 for an example.",
        },
        {   name => "4hour RSI below 30 mad - SHORT NOW !",
            enabled => 1,
            args => {
                expression  => "4hour(previous(rsi(close,14),1) < 30 and previous(rsi(close,14),2) < 30 and previous(rsi(close,14), 3) < 30) and 15minute(rsi(close,14) > 65)",
                timeframe => "15min",
                start_period=> "2 hour ago",
                instruments => $all_instruments,
                item_count  => 1,
            },
            signal_check_interval => 900,
            description => "RSI on 4 hour timeframe is heavily below 30 and rsi on 15 min timeframe is above 65",
            stop_loss => {
                expression => "max(high,2)",
                timeframe => "day",
            },
        },
        {   name => "4hour RSI above 70 mad - LONG NOW !",
            enabled => 1,
            args => {
                expression  => "4hour(previous(rsi(close,14),1) > 70 and previous(rsi(close,14),2) > 70 and previous(rsi(close,14), 3) > 70) and 15minute(rsi(close,14) < 35)",
                timeframe => "15min",
                start_period=> "2 hour ago",
                instruments => $all_instruments,
                item_count  => 1,
            },
            signal_check_interval => 900,
            description => "RSI on 4 hour timeframe is heavily above 70 and rsi on 15 min timeframe is below 35",
            stop_loss => {
                expression => "min(low,2)",
                timeframe => "day",
            },
        },
        {   name => "day ATR double average",
            args => {
                expression  => "tr()>2*previous(atr(14),1)",
                timeframe => "day",
                start_period=> "4 hour ago",
                instruments => $all_instruments,
                item_count  => 1,
            },
            signal_check_interval => 7200,
            description => "Daily range double the 14 day average",
        },
        {   name => "INCOME: Accumulate Long",
            enabled => 1,
            args => {
                expression  => "15minute(rsi(close,14)<30) and 4hour(rsi(close,14) < 42)",
                timeframe   => "15min",
                start_period=> "2 hours ago",
                max_loaded_items => 10000,
                instruments => "USDCHF",
            },
            signal_check_interval => 300,
            description => "Build up long position in instrument with most favourable yield.",
        },
#        {   name => "INCOME: Accumulate Short",
#            enabled => 0,
#            args => {
#                expression  => "15minute(rsi(close,14)>70) and 4hour(rsi(close,14) > 58)",
#                timeframe   => "15min",
#                start_period=> "2 hours ago",
#                max_loaded_items => 10000,
#                instruments => "USDJPY",
#            },
#            signal_check_interval => 300,
#            description => "Build up short position in instrument with most favourable yield.",
#        },
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


    );

#    my %stats = get_descriptive_statistics($all_instruments);
#    foreach my $instrument (keys %stats) {
#        push @signals, {
#            name    => "RANGE $instrument LONG",
#            args    => {
#                expression  => "close > previous(close,1) + (previous(tr(),1) * $stats{$instrument}{percentiles}{90})",
#                timeframe   => "day",
#                start_period=> "24 hours ago",
#                max_loaded_items=> 10,
#                instruments => $instrument,
#            },
#            signal_check_interval   => 60,
#            trigger_minimum_interval => 3600,
#            description => "",
#        }, {
#            name    => "RANGE $instrument SHORT",
#            args    => {
#                expression  => "close < previous(close,1) - (previous(tr(),1) * $stats{$instrument}{percentiles}{90})",
#                timeframe   => "day",
#                start_period=> "24 hours ago",
#                max_loaded_items=> 10,
#                instruments => $instrument,
#            },
#            signal_check_interval   => 60,
#            trigger_minimum_interval => 3600,
#            description => "",
#        };
#    }

    foreach my $signal (@signals) {
        my $signal_name = $signal->{name};
        if (exists($signal->{enabled}) && !$signal->{enabled}) {
            $logger->debug("$signal_name: skip");
            next;
        }
        $logger->debug("$signal_name: begin");
        check_alert($signal);
        $logger->debug("$signal_name: end");
    }

    sleep(5);
}

## NOTE: These methods all take a $signal as an argument
## TODO: Refactor into a Signal class

# Checks if $signal has occured and sends an alert.
sub check_alert {
    my $signal = shift;

    return unless (_wants_signal_check($signal));
    my %args = %{ $signal->{args} };
    my @instruments = split(/,/, delete $args{instruments});
    my @instruments_to_check;
    foreach my $instrument (@instruments) {
        push @instruments_to_check, $instrument if _wants_alert($signal, $instrument);
    }

    return unless(@instruments_to_check);

    $args{instruments} = join(',', @instruments_to_check);
    my $query_string = join("&", map { "$_=$args{$_}" } keys(%args));
    my $url = "$api_base/signalsp?$query_string";
    my $signal_name = $signal->{name};

    $logger->debug("$signal_name: $url");

    my $result;
    eval {
        $result = get_endpoint_result($url);
        1;
    } or do {
        $logger->error("$signal_name: $@");
        $redis->hset("lastSignalCheckError", $signal_name, time());
        return;
    };

    my @instruments_triggered = sort keys(%$result);
    foreach my $instrument (@instruments_triggered) {
        if (@{$result->{$instrument}->{data}}) {
            my $email_message_body = "$instrument\t$result->{$instrument}->{data}->[0]";
            if ( $signal->{stop_loss} ) {
                my $position_size_data = calculatePositionSize($instrument, 300, $signal->{stop_loss});
                my $entry   = $position_size_data->{current_price};
                my $exit    = $position_size_data->{exit};
                my $size    = $position_size_data->{size};

                $email_message_body .= "\t$entry\t$exit\t$size";
            }
            $logger->info("$signal_name: TRIGGER ALERT $email_message_body");
            zap( { subject => "FXAPI: $instrument - $signal_name", message => "$email_message_body\n\n$url" } );
            $logger->debug("$signal_name: set lastSignalAlert $instrument");
            $redis->hset( "lastSignalAlert", $signal_name.$instrument => time() );
        }
    }

    $redis->hset("lastSignalCheckSuccess", $signal_name, time());

    if (!@instruments_triggered) {
        $logger->debug("$signal_name: No trigger");
    }

}

# When a signal is triggered, we don't want to send the same alert multiple sequential times
# Hence a minimum trigger interval is set, and triggers won't fire unless X seconds have elapsed since the
# last trigger.
# Returns true if we want to send a trigger, or false if we don't want to send a trigger because one has already been sent and trigger_minimum_interval has not elapsed.
sub _wants_alert {
    my $signal = shift;
    my $instrument = shift;
    my $signal_name = $signal->{name};

    my $lastSignalAlertTime = $redis->hget("lastSignalAlert", $signal_name.$instrument);
    $logger->debug("$signal_name: checking $instrument");
    return 1 if (!$lastSignalAlertTime);
    my $trigger_minimum_interval = $signal->{trigger_minimum_interval} || 14400;
    my $triggered_seconds_ago = time() - $lastSignalAlertTime;

    $logger->debug("$signal_name: $instrument triggered $triggered_seconds_ago seconds ago, minimum_interval is $trigger_minimum_interval");
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
        $logger->debug("$signal_name: Error occurred $timeSinceLastError seconds ago, waiting for at least 60 seconds");
        return 0;
    }


    my $signal_interval = $signal->{signal_check_interval} || $logger->logdie("$signal_name: No interval defined");
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

sub get_descriptive_statistics {
    $logger->debug("get_descriptive_statistics: retrieving updated statistics");
    my $instruments = shift;
    my $data = get_endpoint_result("$api_base/descriptivestatistics?expression=previous(tr()/previous(atr(14),1),1)&instruments=$instruments");

    return %$data;
}

sub get_screen_result {
    $logger->debug("get_screen_result: Refreshing symbols");
    my $data = get_endpoint_result("$api_base/screener?expression=rsi(close,14)&timeframe=day");

    return $data->[0], $data->[scalar(@$data)-1];
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

    my $result = get_endpoint_result("$api_base/indicators?${parameters}&instruments=${instrument}");

    return $result->{$instrument}{data}[0][1];
}

sub get_endpoint_result {
    my $url = shift;

    my $ua = LWP::UserAgent->new();
    $logger->trace("Fetching $url");

    my $response = $ua->get( $url );
    $logger->logconfess($!) unless($response->is_success);

    my $content = $response->content;
    my $d = decode_json($content);

    return $d->{results};
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
