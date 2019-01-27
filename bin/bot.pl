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
use MCE::Loop;
use MCE::Queue;


my $log_conf = q(
log4perl rootLogger = INFO, SCREEN
log4perl.appender.SCREEN         = Log::Log4perl::Appender::Screen
log4perl.appender.SCREEN.stderr  = 0
log4perl.appender.SCREEN.layout  = Log::Log4perl::Layout::PatternLayout
log4perl.appender.SCREEN.layout.ConversionPattern = %d{ISO8601} [%P][%x] %m %n
);
Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();


my $targets = MCE::Queue->new( fast => 1 );

my $datetime_formatter = DateTime::Format::RFC3339->new();

my $cfg = Finance::HostedTrader::Config->new();
my $oanda = $cfg->provider('oanda');
$oanda->datetime_format('UNIX' );

my @instrument_names = $oanda->getInstruments();
#@instrument_names = grep /AUD_/, $oanda->getInstruments();

my $max_workers = 2;
MCE::Loop::init {
    max_workers => $max_workers, chunk_size => int( (scalar(@instrument_names) / $max_workers)  + 0.5)
};

$logger->info("Start");

my %instruments = mce_loop {
    my ($mce, $chunk_ref, $chunk_id) = @_;

    foreach my $instrument_name (@$chunk_ref) {
        Log::Log4perl::NDC->push($instrument_name);

        my $dataset;
        $logger->info("fetch historical data begin");
        foreach my $timeframe (qw/60 900 86400/) {
            my $data = $oanda->getHistoricalData($instrument_name, $timeframe, 200);
            my $thisTimeStamp       = $data->{candles}[$#{ $data->{candles} }]{time};
            $dataset->{timeframes}{$timeframe}{lastTimeStampCandle}  = int($thisTimeStamp / $timeframe);
            $dataset->{timeframes}{$timeframe}{data}{open}  = [ map { $_->{mid}{o} } @{ $data->{candles} } ];
            $dataset->{timeframes}{$timeframe}{data}{high}  = [ map { $_->{mid}{h} } @{ $data->{candles} } ];
            $dataset->{timeframes}{$timeframe}{data}{low}   = [ map { $_->{mid}{l} } @{ $data->{candles} } ];
            $dataset->{timeframes}{$timeframe}{data}{close} = [ map { $_->{mid}{c} } @{ $data->{candles} } ];

            my $item_count = scalar( @{ $dataset->{timeframes}{$timeframe}{data}{close} });
            if (scalar ( @{ $dataset->{timeframes}{$timeframe}{data}{open} } ) != $item_count ) {
                $logger->die("[tf=$timeframe] Number of open datapoints differs to number of closing candles");
            }

            if (scalar ( @{ $dataset->{timeframes}{$timeframe}{data}{high} } ) != $item_count ) {
                $logger->die("[tf=$timeframe] Number of high datapoints differs to number of closing candles");
            }

            if (scalar ( @{ $dataset->{timeframes}{$timeframe}{data}{low} } ) != $item_count ) {
                $logger->die("[tf=$timeframe] Number of low datapoints differs to number of closing candles");
            }

        }
        $logger->info("fetch historical data end");

        Log::Log4perl::NDC->pop();

        MCE->gather( $instrument_name => $dataset );
    }

} @instrument_names;

if (scalar(keys %instruments) != scalar(@instrument_names)) {
    $logger->logdie("Failed to download data for some instruments");
}

$logger->info("Done");

my $mce = MCE->new(

   task_end => sub {
      my ($mce, $task_id, $task_name) = @_;
      $logger->info("done with task $task_name");
      $targets->end() if $task_name eq 'calculate_indicators';
   },

    user_tasks => [
    {
        max_workers => 1,
        task_name => 'calculate_indicators',
        user_func => sub {

            my $rsi_up  = 80;
            my $rsi_down= 20;
            while (1) {

                $logger->info("START STREAM");

                my $http_response = $oanda->streamPriceData(\@instrument_names, sub {
                    my $obj = shift;

                    my $instrument_name = $obj->{instrument};
                    Log::Log4perl::NDC->push($instrument_name);

                    my $instrument_info = $instruments{$instrument_name};
                    my $tfs = $instrument_info->{timeframes};
                    calc_indicators($instrument_info, $obj);

                    my $rsi_15min = $tfs->{900}{rsi};

                    if ($rsi_15min > $rsi_up) {
                        $tfs->{900}{signals}{long}{last_rsi_trigger} = time();
                    } elsif ($rsi_15min < $rsi_down) {
                        $tfs->{900}{signals}{short}{last_rsi_trigger} = time();
                    }

                    if ($rsi_15min > $rsi_up || $rsi_15min < $rsi_down) {
                        $tfs->{900}{signals}{long}{last_rsi_trigger} = time();
                        $logger->info("Adding to queue");
                        $targets->enqueue( { direction => ($rsi_15min > 70 ? 'L' : 'S'), instrument_name => $instrument_name } );
                        my $datetime = $instrument_info->{lastTickDateTime};
                        my $thisPrice = $tfs->{900}{data}{close}[ $#{ $tfs->{900}{data}{close} } ];
#                        $logger->info("$datetime\t$thisPrice\t", sprintf("%.2f",$rsi_15min), "\t", sprintf("%.2f", $tfs->{60}{rsi}));
                        $logger->info("$datetime\t$thisPrice\t", sprintf("%.2f",$rsi_15min), "\t", sprintf("%.2f", $tfs->{60}{rsi}), "\t", sprintf("%.4f", $tfs->{86400}{atr}));
                    }

                    Log::Log4perl::NDC->pop();
                });

                $logger->info("EXIT STREAM\t" . $http_response->status_line . "\t" . $http_response->decoded_content);
                sleep(1);
            }
        },
    },
    {
        max_workers => 2,
        task_name   => 'enter_positions',
        user_func => sub {
            ## This sub only has access to the data that was added to the $targets queue
            ## It does not have access to an up 2 date copy of the global variable %instruments
            while (defined (my $target = $targets->dequeue)) {
                Log::Log4perl::NDC->push($target->{instrument_name});
                $logger->info("processed from queue");
                Log::Log4perl::NDC->pop();
            }
        },
    }
    ],

)->run();

sub calc_indicators {
    my $instrument_info = shift;
    my $latest_tick = shift;

    my @timeframes = keys %{ $instrument_info->{timeframes} };

    my $thisPrice = $latest_tick->{closeoutBid} + (($latest_tick->{closeoutAsk} - $latest_tick->{closeoutBid}) / 2);
    my $thisTimestamp = $latest_tick->{time};
    my $datetime = $datetime_formatter->format_datetime(DateTime->from_epoch(epoch => $thisTimestamp));
    $instrument_info->{lastTickDateTime} = $datetime;

    foreach my $timeframe (@timeframes) {
        my $thisTimeStampCandle = int($thisTimestamp / $timeframe);
        my $tf = $instrument_info->{timeframes}{$timeframe};

        if ($tf->{lastTimeStampCandle} == $thisTimeStampCandle) {
            $tf->{data}{close}[ $#{ $tf->{data}{close}} ] = $thisPrice;
            if ( $thisPrice > $tf->{data}{high}[ $#{ $tf->{data}{high}} ]) {
                $tf->{data}{high}[ $#{ $tf->{data}{high}} ] = $thisPrice;
            }
            if ( $thisPrice < $tf->{data}{low}[ $#{ $tf->{data}{low}} ]) {
                $tf->{data}{low}[ $#{ $tf->{data}{low}} ] = $thisPrice;
            }
        } elsif ($tf->{lastTimeStampCandle} < $thisTimeStampCandle) {
            while ($tf->{lastTimeStampCandle} < $thisTimeStampCandle) {
                shift @{ $tf->{$timeframe}{data}{close} };
                if ($tf->{lastTimeStampCandle} == $thisTimeStampCandle - 1) {
                    push @{ $tf->{data}{open} }, $thisPrice;
                    push @{ $tf->{data}{high} }, $thisPrice;
                    push @{ $tf->{data}{low} }, $thisPrice;
                    push @{ $tf->{data}{close} }, $thisPrice;
                } else {
                    push @{ $tf->{data}{open} }, $tf->{data}{close}[ $#{ $tf->{data}{close} } ];
                    push @{ $tf->{data}{high} }, $tf->{data}{close}[ $#{ $tf->{data}{close} } ];
                    push @{ $tf->{data}{low} }, $tf->{data}{close}[ $#{ $tf->{data}{close} } ];
                    push @{ $tf->{data}{close} }, $tf->{data}{close}[ $#{ $tf->{data}{close} } ];
                }
                $tf->{lastTimeStampCandle} += 1;
            }
        } else {
            $logger->logconfess("Received tick from past timeframe candle");
        }

        my @ret = TA_RSI(0, $#{ $tf->{data}{close} }, $tf->{data}{close}, 14);
        $tf->{rsi} = $ret[2][$#{$ret[2]}];

        @ret = TA_ATR(0, $#{ $tf->{data}{close} }, $tf->{data}{high}, $tf->{data}{low}, $tf->{data}{close}, 14);
        if ($timeframe == 86400) {
#            $logger->info(Dumper(\$ret[2]));
        }
        $tf->{atr} = $ret[2][$#{$ret[2]}];
    }
}
