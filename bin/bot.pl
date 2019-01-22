#!/usr/bin/perl

# ABSTRACT: Demo oanda v20 api
# PODNAME: bot.pl

use v5.10;
use strict;
use warnings;

$|=1;

use Finance::HostedTrader::Config;

use IO::Handle;
use Net::HTTP;
use Net::HTTPS;

use Finance::TA;
use DateTime;
use DateTime::Format::RFC3339;
use Data::Dumper;
use Log::Log4perl;
use MCE;
use MCE::Queue;


my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} %x %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();


my $targets = MCE::Queue->new( fast => 1 );

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format('UNIX' );

my @instrument_names = $oanda->getInstruments();
#@instrument_names = grep /USD_/, $oanda->getInstruments();

my $instruments;
foreach my $instrument_name (@instrument_names) {
    Log::Log4perl::NDC->push($instrument_name);

    $logger->info("FETCH HISTORICAL DATA");
    #print "FETCH HISTORICAL DATA $instrument_name\n";

    foreach my $timeframe (qw/ 60 900/) {
        my $data = $oanda->getHistoricalData($instrument_name, $timeframe, 200);
        my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
        $instruments->{$instrument_name}{timeframes}{$timeframe}{lastTimeStampBlock}  = int($thisTimeStamp / $timeframe);
        $instruments->{$instrument_name}{timeframes}{$timeframe}{data} = [ map { $_->{mid}{c} } @{ $data->{candles} } ];
    }

    Log::Log4perl::NDC->pop();
}

my $mce = MCE->new(

   task_end => sub {
      my ($mce, $task_id, $task_name) = @_;
      print "done with task $task_name\n";
      MCE->say("done with task $task_name");
      $targets->end() if $task_name eq 'calculate_indicators';
   },

    user_tasks => [
    {
        max_workers => 1,
        task_name => 'calculate_indicators',
        user_func => sub {
            my %skip;
            while (1) {

                #MCE->say("START STREAM");
                $logger->info("START STREAM");

                my $http_response = $oanda->streamPriceData(\@instrument_names, sub {
                    my $obj = shift;

                    my $instrument_name = $obj->{instrument};
                    Log::Log4perl::NDC->push($instrument_name);

                    calc($instruments->{$instrument_name}, $obj);
                    #print Dumper($instruments->{$instrument_name});
                    my $rsi = $instruments->{$instrument_name}{timeframes}{900}{rsi};

                    if ($rsi > 75 || $rsi < 25) {
                        MCE->say("Adding $instrument_name to queue");
                        $targets->enqueue( { direction => ($rsi > 70 ? 'L' : 'S'), instrument => $instrument_name } );
                        $skip{$instrument_name} = 1; #TODO: When/How does skip go back to 0 ?
                        my $datetime = $instruments->{$instrument_name}{lastTickDateTime};
                        my $thisPrice = $instruments->{$instrument_name}{timeframes}{900}{data}[ $#{ $instruments->{$instrument_name}{timeframes}{900}{data} } ];
                        $logger->info("$datetime\t$thisPrice\t", sprintf("%.2f",$rsi), "\t", sprintf("%.2f", $instruments->{$instrument_name}{timeframes}{60}{rsi}));
                        #MCE->say("$datetime\t$thisPrice\t", sprintf("%.2f",$rsi), "\t", sprintf("%.2f", $instruments->{$instrument_name}{timeframes}{60}{rsi}));
                    }

                    Log::Log4perl::NDC->pop();
                    return 1;
                });

                $logger->info("EXIT STREAM\t" . $http_response->status_line . "\t" . $http_response->decoded_content);
                #MCE->say("EXIT STREAM\t" . $http_response->status_line . "\t" . $http_response->decoded_content);
                sleep(1);
            }
        },
    },
    {
        max_workers => 2,
        task_name   => 'enter_positions',
        user_func => sub {
            while (defined (my $target = $targets->dequeue)) {
                MCE->say("Removed $target->{instrument} from queue");
            }
        },
    }
    ],

)->run();

sub calc {
    my $instrument_info = shift;
    my $latest_tick = shift;

    my @timeframes = keys %{ $instrument_info->{timeframes} };

    my $thisPrice = $latest_tick->{closeoutBid} + (($latest_tick->{closeoutAsk} - $latest_tick->{closeoutBid}) / 2);
    my $thisTimestamp = $latest_tick->{time};
    my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
    $instrument_info->{lastTickDateTime} = $datetime;

    foreach my $timeframe (@timeframes) {
        my $thisTimeStampBlock = int($thisTimestamp / $timeframe);
        #my $datetime_this_block = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimeStampBlock*$timeframe));

        if ($instrument_info->{timeframes}{$timeframe}{lastTimeStampBlock} == $thisTimeStampBlock) {
            $instrument_info->{timeframes}{$timeframe}{data}[ $#{ $instrument_info->{timeframes}{$timeframe}{data}} ] = $thisPrice
        } elsif ($instrument_info->{timeframes}{$timeframe}{lastTimeStampBlock} < $thisTimeStampBlock) {
            while ($instrument_info->{timeframes}{$timeframe}{lastTimeStampBlock} < $thisTimeStampBlock) {
                shift @{ $instrument_info->{timeframes}{$timeframe}{data} };
                if ($instrument_info->{timeframes}{$timeframe}{lastTimeStampBlock} == $thisTimeStampBlock - 1) {
                    push @{ $instrument_info->{timeframes}{$timeframe}{data} }, $thisPrice;
                } else {
                    push @{ $instrument_info->{timeframes}{$timeframe}{data} }, $instrument_info->{timeframes}{$timeframe}{data}[ $#{ $instrument_info->{timeframes}{$timeframe}{data} } ];
                }
                $instrument_info->{timeframes}{$timeframe}{lastTimeStampBlock} += 1;
            }
        } else {
            $logger->logconfess("Received tick from past timeframe candle");
        }

        my @ret = TA_RSI(0, $#{ $instrument_info->{timeframes}{$timeframe}{data} }, $instrument_info->{timeframes}{$timeframe}{data}, 14);
        my $rsi = $ret[2][$#{$ret[2]}];
        $instrument_info->{timeframes}{$timeframe}{rsi} = $rsi;
    }
}
