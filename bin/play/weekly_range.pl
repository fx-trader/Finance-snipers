#!/usr/bin/perl

# Prints all instruments sorted by how much they moved in the latest weekly period

use strict;
use warnings;

use Finance::HostedTrader::Config;
use Finance::HostedTrader::Datasource;
use Data::Dumper;


my $c       = Finance::HostedTrader::Config->new();
my $instruments = $c->symbols->natural;
my $dbh     = Finance::HostedTrader::Datasource->new()->dbh();

my @inner_queries;
my $table_count = 0;
my $all_tables  = '';
my @all_fields;

foreach my $instrument (@$instruments) {
    $table_count++;
    $all_tables .= "T${table_count}.${instrument}";
    my $on_clause="";
    if ($table_count > 1) {
        $on_clause = "ON T1.datetime = T${table_count}.datetime";
    }
    push @inner_queries, "(SELECT datetime, 100*(high-low)/low AS $instrument FROM ${instrument}_604800 ORDER BY datetime DESC LIMIT 100) AS T${table_count} $on_clause ";
    push @all_fields, "T${table_count}.${instrument}";
}


my $sql = "SELECT T1.datetime, " . join(",", @all_fields) . " FROM " . join(" INNER JOIN \n", @inner_queries) . " LIMIT 1";
my $data = $dbh->selectrow_hashref($sql);
delete $data->{datetime};
print Dumper($data);
foreach my $name (sort { $data->{$b} <=> $data->{$a} } keys %$data) {
printf "%-8s %s\n", $name, $data->{$name};
}
