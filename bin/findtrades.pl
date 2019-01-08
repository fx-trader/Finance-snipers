#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;



my $emafilter = Filter::EMARatio->new();
my $rsifilter = Filter::RSI->new();

my %tradeable;

my $results = $emafilter->filter();

my (%longs, %shorts);

foreach my $result (@{ $results->{long} }) {
    $longs{$result->[0]}++;
}
foreach my $result (@{ $results->{short} }) {
    $shorts{$result->[0]}++;
}


$results = $rsifilter->filter();

foreach my $result (@{ $results->{long} }) {
    $longs{$result->[0]}++;
}
foreach my $result (@{ $results->{short} }) {
    $shorts{$result->[0]}++;
}


print "Long : ", join(", ", keys %longs), "\n";
print "Short: ", join(", ", keys %shorts), "\n";


package Filter::EMARatio;

use Moo;

sub filter {
    my $self = shift;

    my $fxapi = FXAPI->new();
    my $data = $fxapi->screen( expression => "close/ema(close,200)" );

    my %results;

    # Ignore instruments where we don't have enough data to calculate ema200
    my @results = grep { defined($_->[2]) } @{ $data->{results} }; 

    my @sorted = sort {
        my $v1 = $a->[2] > 1 ? $a->[2] - 1 : 1 - $a->[2];
        my $v2 = $b->[2] > 1 ? $b->[2] - 1 : 1 - $b->[2];

        $v2 <=> $v1;
    } @results;


    foreach my $item (@sorted[0..2]) {
        push @{ $results{ $item->[2] > 1 ? 'long' : 'short' } }, $item;
    }

    return \%results;
}

1;

package Filter::RSI;

use strict;
use warnings;

use Moo;

#extends Filter;

sub filter {
    my $self = shift;

    my $fxapi = FXAPI->new();
    my $data = $fxapi->screen( expression => "rsi(close,14)" );

    my %results;

    my @sorted = sort {
        my $v1 = $a->[2] > 50 ? 100 - $a->[2] : $a->[2];
        my $v2 = $b->[2] > 50 ? 100 - $b->[2] : $b->[2];

        $v1 <=> $v2;
    } @{ $data->{results} };


    foreach my $item (@sorted[0..2]) {
        push @{ $results{ $item->[2] > 50 ? 'long' : 'short' } }, $item;
    }

    return \%results;
}

1;

package FXAPI;

use strict;
use warnings;

use Moo;

use LWP::Simple;
use JSON;
use URI::Query;


sub screen {
    my $self = shift;

    my %args = @_;
    my $qq = URI::Query->new(\%args);

    my $url = "/screener?" . $qq->stringify;
    return $self->fetch_url($url);

}

sub fetch_url {
    my $self = shift;

    my $url = "http://api.fxhistoricaldata.com" . shift;
    my $content = get($url);
    die($!) unless($content);
    return from_json($content);
}

1;
