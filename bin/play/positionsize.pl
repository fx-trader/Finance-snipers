#!/usr/bin/perl

use strict;
use warnings;

use Finance::HostedTrader::Config;
my $symbols = Finance::HostedTrader::Config->new()->symbols();

my $all_instruments = "AUDUSD,AUDJPY,AUDNZD,CHFJPY,EURCAD,EURCHF,EURGBP,EURJPY,EURUSD,GBPCHF,GBPJPY,GBPNZD,GBPUSD,NZDUSD,NZDJPY,USDCAD,USDCHF,USDHKD,USDJPY,XAUUSD,XAGUSD,AUS200,ESP35,FRA40,GER30,HKG33,JPN225,NAS100,SPX500,UK100,UKOil,US30,USOil,USDOLLAR,Bund";

foreach my $instrument (split(",", $all_instruments)) {

my $data = calculatePositionSize($instrument, 200, "short");

print "$instrument - " . Dumper($data);use Data::Dumper;
}

sub getRatioCurrency {
    my ($symbol) = @_;

    my $symbolCurrency = $symbols->getSymbolDenominator($symbol);
    my $accountCurrency = 'GBP'; #TODO, hardcoded to GBP
    if ($symbolCurrency eq $accountCurrency) {
        return;
    }

    my $ratio_symbol = "${accountCurrency}${symbolCurrency}";
    return $ratio_symbol;
}

sub calculatePositionSize {
use POSIX;
    my ($symbol, $maxLoss, $direction) = @_;

    my $exit_expression = ( $direction eq 'long' ? 'min(low,2)' : 'max(high,2)' );

    my $entry = get_endpoint_result_scalar("timeframe=5min&expression=close", $symbol);
    my $exit = get_endpoint_result_scalar("timeframe=day&expression=${exit_expression}", $symbol);

    my $ratioCurrency = getRatioCurrency($symbol);
    my $positionSize;
    if ($ratioCurrency) {
        my $ratio = get_endpoint_result_scalar("timeframe=5min&expression=close", $ratioCurrency);
        $positionSize = POSIX::floor( $maxLoss * $ratio / ($entry - $exit) ) / $symbols->getSymbolMeta2($symbol);
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
    my $symbol = shift;

    my $result = get_endpoint_result("http://api.fxhistoricaldata.com/v1/indicators?${parameters}&instruments=${symbol}");

    return $result->{$symbol}{data}[0][1];
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
