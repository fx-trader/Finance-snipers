#!/usr/bin/perl

# Query that produces the max weekly range for all symbols

use strict;
use warnings;

use Finance::HostedTrader::Config;
use Data::Dumper;


my $c       = Finance::HostedTrader::Config->new();
my $symbols = $c->symbols->natural;

my @inner_queries;
my $table_count = 0;
my $all_tables  = '';
my @all_fields;

foreach my $symbol (@$symbols) {
    $table_count++;
    $all_tables .= "T${table_count}.${symbol}";
    my $on_clause="";
    if ($table_count > 1) {
        $on_clause = "ON T1.datetime = T${table_count}.datetime";
    }
    push @inner_queries, "(SELECT datetime, 100*(high-low)/low AS $symbol FROM ${symbol}_604800 ORDER BY datetime DESC LIMIT 100) AS T${table_count} $on_clause ";
    push @all_fields, "T${table_count}.${symbol}";
}


print "SELECT T1.datetime, GREATEST(" . join(",", @all_fields) . ") FROM " . join(" INNER JOIN \n", @inner_queries);
