#!/versions/perl-5.20.0/bin/perl

use strict;
use warnings;

$|=1;

use Log::Log4perl;
use LWP::Simple;
use LWP::UserAgent;
use JSON::MaybeXS;
use Data::Dumper;

my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
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



my $api_base = "http://api.fxhistoricaldata.com/v1";
#my $api_base = "http://172.17.0.1:5001";

#my $all_instruments = join(",", @{ get_all_instruments() });
my $all_instruments = "AUDUSD,AUDJPY,AUDNZD,CHFJPY,EURCAD,EURCHF,EURGBP,EURJPY,EURUSD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDUSD,NZDJPY,USDCAD,USDCHF,USDHKD,USDJPY,XAUUSD,XAGUSD,AUS200,ESP35,FRA40,GER30,HKG33,JPN225,NAS100,SPX500,UK100,UKOil,US30,USOil,USDOLLAR,Bund";
my %signals = (
#    "trend_reverse" => {
#        args => {
#            expression  => "day(min(rsi(close,14),15)<35 and min(close,20) <= min(close,100)) and 4hour(crossoverup(ema(close,20),ema(close,200)))",
#            start_period=> "one hour ago",
#            instruments => join(",", @{ get_all_instruments() }),
#            item_count  => 1,
#        },
#        interval => 300,
#        description => "",
#    },
    "bouncing_cat" => {
        args => {
            #expression  => "day(open > close and tr()>2*atr(14)) and 15minute(rsi(close,14)>60)",
            expression  => "tr()>2*atr(14)",
            timeframe => "day",
            start_period=> "1 hour ago",
            instruments => $all_instruments,
            item_count  => 1,
        },
        interval => 7200,
        description => "Range double the average",
    },
    "strong_USD" => {
        args => {
            expression  => "4hour(rsi(close,14) < 42) and 15minute(rsi(close,14) < 38)",
            start_period=> "1 hour ago",
            instruments => "USDOLLAR",
        },
        interval => 300,
        description => "Long USD weakness",
    },
    "daily_retraction" => {
        args => {
            expression  => "min(low,5)%2B0.5*atr(14) > previous(max(close,50),50) and rsi(close,14)<38",
            timeframe   => "day",
            start_period=> "1 hour ago",
            max_loaded_items => 50000,
            instruments => $all_instruments,
        },
        interval => 10200,
        description => "Retracement to support",
    },
);

my %lastSignalCheck = map { $_ => 0 } keys %signals;

while (1) {
    foreach my $signal_name (keys %signals) {
        my $signal = $signals{$signal_name};

        $logger->info("$signal_name: begin");
        my $signal_interval = $signal->{interval} || $logger->logdie("No interval defined for signal $signal_name");
        my $signal_check_in = $lastSignalCheck{$signal_name} + $signal_interval - time();
        if ( $signal_check_in > 0 ) {
            $logger->info("$signal_name: due in $signal_check_in seconds");
            next;
        }
        my $results = get_signal($signal);
        if ($results) {
            $logger->info("$signal_name: $results");
            zap( { subject => "fx-signal-check: $signal_name", message => $results } );
        } else {
            $logger->info("$signal_name: No trigger");
        }
        $lastSignalCheck{$signal_name} = time();
    }

    $logger->info("Sleeping");
    sleep(30);
}

sub get_signal {
    my $signal = shift;

    my $args = $signal->{args};

    my $query_string = join("&", map { "$_=$args->{$_}" } keys(%$args));
    my $url = "$api_base/signals?$query_string";

    $logger->debug($url);

    my $result = get_endpoint_result($url);

    my $results = '';
    foreach my $instrument (sort keys %$result) {
        if (@{$result->{$instrument}->{data}}) {
            $results .= "$instrument\t$result->{$instrument}->{data}->[0]\n";
        }
    }
    return $results;
}

sub get_all_instruments {
    return get_endpoint_result("$api_base/instruments");
}

sub get_endpoint_result {
    my $url = shift;
    my $content = get($url);

    $logger->debug("Fetching $url");
    die($!) unless($content);

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
