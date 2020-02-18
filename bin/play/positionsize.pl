#!/usr/bin/perl

use strict;
use warnings;

use Finance::HostedTrader::Config;
my $instruments = Finance::HostedTrader::Config->new()->symbols();

my $all_instruments = "AUDUSD,AUDJPY,AUDNZD,CHFJPY,EURCAD,EURCHF,EURGBP,EURJPY,EURUSD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDUSD,NZDJPY,USDCAD,USDCHF,USDHKD,USDJPY,XAUUSD,XAGUSD,AUS200,ESP35,FRA40,GER30,HKG33,JPN225,NAS100,SPX500,UK100,UKOil,US30,USOil,USDOLLAR,Bund";

foreach my $instrument (split(",", $all_instruments)) {

my $data = calculatePositionSize($instrument, 200, "short");

print "$instrument - " . Dumper($data);use Data::Dumper;
}

sub getRatioCurrency {
    my ($instrument) = @_;

    my $instrumentCurrency = $instruments->getSymbolDenominator($instrument);
    my $accountCurrency = 'GBP'; #TODO, hardcoded to GBP
    if ($instrumentCurrency eq $accountCurrency) {
        return;
    }

    my $ratio_instrument = "${accountCurrency}${instrumentCurrency}";
    return $ratio_instrument;
}

sub calculatePositionSize {
use POSIX;
    my ($instrument, $maxLoss, $direction) = @_;

    my $exit_expression = ( $direction eq 'long' ? 'min(low,2)' : 'max(high,2)' );

    my $entry = get_endpoint_result_scalar("timeframe=5minute&expression=close", $instrument);
    my $exit = get_endpoint_result_scalar("timeframe=day&expression=${exit_expression}", $instrument);

    my $ratioCurrency = getRatioCurrency($instrument);
    my $positionSize;
    if ($ratioCurrency) {
        my $ratio = get_endpoint_result_scalar("timeframe=5minute&expression=close", $ratioCurrency);
        $positionSize = POSIX::floor( $maxLoss * $ratio / ($entry - $exit) ) / $instruments->getSymbolMeta2($instrument);
    } else {
        $positionSize = POSIX::floor( $maxLoss / ($entry - $exit) );
    }

    return {
        entry   => $entry,
        exit    => $exit,
        size    => $positionSize,
        maxLoss => $maxLoss,
    };
}

sub get_endpoint_result_scalar {
    my $parameters = shift;
    my $instrument = shift;

    my $result = get_endpoint_result("http://api.fxhistoricaldata.com/indicators?${parameters}&instruments=${instrument}");

    return $result->{$instrument}{data}[0][1];
}

sub get_endpoint_result {
use LWP::UserAgent;
use JSON::MaybeXS;
    my $url = shift;

    my $ua = LWP::UserAgent->new();

    print "$url\n";
    my $response = $ua->get( $url );
    die($!) unless($response->is_success);

    my $content = $response->content;
    my $d = decode_json($content);

    return $d->{results};
}
