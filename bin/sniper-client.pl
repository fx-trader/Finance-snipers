#!/usr/bin/perl

use strict;
use warnings;

$|=1;
use Log::Log4perl;
use JSON::MaybeXS;
use Data::Dumper;

my $log_level = $ENV{LOG_LEVEL} // 'INFO';
# Initialize Logger
my $log_conf = qq(
log4perl rootLogger = $log_level, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = \%d{ISO8601} \%m \%n
);

Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();

my $check_interval = 20;

checkOandaToken();

while (1) {

    $logger->debug("Sleeping $check_interval seconds");
    sleep($check_interval);
    my $snipers = GET_json('http://api.fxhistoricaldata.com/snipers');

    foreach my $sniper (@$snipers) {
        my $instrument = $sniper->{instrument};
        my $quantity = $sniper->{quantity};
        my $expression = $sniper->{expression};
        my $timeframe = $sniper->{timeframe};

        $logger->info("Instrument = $instrument");
        $logger->info("Quantity = $quantity");

        my $last_signal = getSignalValue(%$sniper);
        if ($last_signal) {
            $logger->info("Sniper engage");

            use Finance::HostedTrader::Config;
            my $provider = Finance::HostedTrader::Config->new()->provider('oanda_demo');
            $provider->openMarket($sniper->{instrument}, $sniper->{quantity});
            DELETE_json("http://api.fxhistoricaldata.com/snipers/" . $sniper->{id});

            # getIndicatorValue is also being called for the side effect of logging the indicator values at INFO level
            # TODO: strictly speaking, the indicator being printed here ought to be a generic expression based on the sniper expression, not hardcoded to be rsi
            #       perhaps this could be achieved by changing the signals API to optionally return indicator values for the expressions being evaluated
            my ($datetime, $rsi, $close) = @{ getIndicatorValue($instrument, '15minute', "rsi(close,14),close") };
            zap( { subject => "fx-sniper: openmarket - $instrument $quantity", message => "DATETIME = $datetime\nRSI=$rsi\nCLOSE=$close" } );
        } else {
            $logger->info("Sniper wait");
        }

    }

}

sub DELETE_json {
    my $url = shift;
    my $client = LWP::UserAgent->new();
    my $req = HTTP::Request->new( DELETE => $url );

    my $response = $client->request($req);
    my $content = $response->decoded_content() // "";

    if (!$response->is_success()) {
        $logger->logconfess("Failed to DELETE $url\n" . $response->status_line . "\n$content");
    } else {
        $logger->info("DELETE $url ok");
    }

    if ($content) {
        my $json_response = decode_json($content);
        return $json_response;
    }
}

sub GET_json {
    my $url = shift;

use LWP::UserAgent;
use JSON::MaybeXS;

    my $client = LWP::UserAgent->new();
    my $response = $client->get($url);

    my $content = $response->decoded_content();
    if (!$response->is_success()) {
        $logger->logconfess("Failed to GET $url\n" . $response->status_line . "\n$content");
    }
    my $json_response = decode_json($content) || $logger->logconfess("Could not decode json response for $url\n$content");
    return $json_response;
}

sub getSignalValue {
    my %args = @_;

    my $instrument = $args{instrument} // $logger->logconfess("missing instrument argument");
    my $tf = $args{timeframe} // $logger->logconfess("missing timeframe argument");
    my $signal = $args{expression} // $logger->logconfess("missing expressions argument");

    my $url = "http://api.fxhistoricaldata.com/signals?instruments=$instrument&expression=$signal&item_count=1&timeframe=$tf&start_period=10 minutes ago&max_loaded_items=20000";
    my $json_response = GET_json($url);
    my $data = $json_response->{results}{$instrument}{data} || $logger->logconfess("json response for $url does not have expected structure\n" . Dumper($json_response));

    $logger->logconfess("Failed to retrieve indicator '$signal'") if (!$data);
    $logger->info("$signal ($tf) = " . (defined($data->[0]) ? $data->[0] : 'null'));

    return $data->[0] if (defined($data->[0]));
    return undef;
}

sub getIndicatorValue {
    my $instrument = shift;
    my $tf = shift;
    my $indicator = shift;


    use LWP::UserAgent;
    use JSON::MaybeXS;

    my $ua = LWP::UserAgent->new();
    my $url = "http://api.fxhistoricaldata.com/indicators?instruments=$instrument&expression=$indicator&item_count=1&timeframe=$tf";

    my $json_response = GET_json($url);

    my $data = $json_response->{results}{$instrument}{data} || $logger->logconfess("json response for $url does not have expected structure\n" . Dumper($json_response));

    $logger->logconfess("Failed to retrieve indicator '$indicator'") if (!$data || !$data->[0]);
    foreach my $value (@{ $data->[0] }) {
        $logger->info("$indicator ($tf) = $value");
    }

    return $data->[0];
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

sub checkOandaToken {
    my $oanda = Finance::HostedTrader::Config->new()->provider('oanda_demo');
    $oanda->getAccountSummary(); ## This is only being called to check that the authentication token is valid.  if it's not, the program dies early.
}
