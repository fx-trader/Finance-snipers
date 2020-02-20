#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: bot.pl

use strict;
use warnings;
use Time::HiRes qw/gettimeofday tv_interval/;
use Benchmark qw/:all/;

$|=1;

use Finance::HostedTrader::Config;
use Finance::TA;
use DateTime;
use DateTime::Format::RFC3339;
use Data::Dumper;
use Log::Log4perl;

my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
#log4perl rootLogger = INFO, LOG1, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
#log4perl.appender.SCREEN.layout.ConversionPattern = %m %n
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();


my $timeframe   = 900;

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format('UNIX' );

my @all_instruments = $oanda->getInstruments();
my $instruments;

foreach my $instrument_name (@all_instruments) {
    #print "[$instrument_name][$$][$chunk_id] Fetch\n";
    $instruments->{$instrument_name}{data} = $oanda->getHistoricalData($instrument_name, $timeframe, 200);
}

my $start = [gettimeofday];
foreach my $instrument_name (@all_instruments) {
    my $data = $instruments->{$instrument_name}{data};
    my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
    $instruments->{$instrument_name}{lastTimeStampBlock}  = int($thisTimeStamp / $timeframe);
    $instruments->{$instrument_name}{dataset}             = [ map { $_->{mid}{c} } @{ $data->{candles} } ];

    my @ret = TA_RSI(0, $#{ $instruments->{$instrument_name}{dataset} }, $instruments->{$instrument_name}{dataset}, 14);
    my $rsi = $ret[2][$#{$ret[2]}];
}
my $elapsed = tv_interval($start);
print scalar(@all_instruments), "\t", $elapsed, "\t", scalar(@all_instruments) / $elapsed, "\n";
