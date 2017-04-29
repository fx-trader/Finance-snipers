#!/usr/bin/perl

use strict;
use warnings;

use Finance::HostedTrader::Config;
my $symbols = Finance::HostedTrader::Config->new()->symbols();

my $data = calculatePositionSize("EURGBP", 200, "short");

print Dumper($data);use Data::Dumper;


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

    my $response = $ua->get( $url );
    die($!) unless($response->is_success);

    my $content = $response->content;
    my $d = decode_json($content);

    return $d->{results};
}
