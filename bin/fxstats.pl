#!/usr/bin/perl

use strict;
use warnings;

use JSON;
use LWP::Simple;
use Data::Dumper;
use Text::ASCIITable;

    my %signals = (
        short   => '/screener?expression=(close-low)/previous(atr(14),1),close,previous(atr(14),1),low',
        long    => '/screener?expression=(high-close)/previous(atr(14),1),close,previous(atr(14),1),high',
    );

    my @work;
    foreach my $key (keys(%signals)) {
        my $d = fetch_url($signals{$key});
        my @result_of_interest = grep { $_->[2] > 1 } @{ $d->{results} };

        foreach my $task (@result_of_interest) {
            push @work, { instrument => $task->[0], direction => $key, range => $task->[2], close => $task->[3], atr14 => $task->[4], pivot => $task->[5] };
        }
    }

    my $instruments = join ",", map { $_->{instrument} } @work;
    print "No instruments to analyse\n" and exit unless($instruments);
    my $url = "/descriptivestatistics?percentiles=85,90,95&expression=tr()/previous(atr(14),1)&instruments=$instruments";
    my $data = fetch_url($url);

    my $table = Text::ASCIITable->new( { headingText => 'Range stats' } );
    $table->setCols('Instrument', 'Direction', 'Pivot', 'ATR14', 'TR/ATR14', 'Close', '85%', '90%', '95%');

    foreach my $task (sort { $b->{range} <=> $a->{range} } @work) {
        my $instrument          = $task->{instrument};
        my $direction           = $task->{direction};
        my $range_now           = $task->{range};
        my $close               = $task->{close};
        my $atr14               = $task->{atr14};
        my $pivot               = $task->{pivot};
        my $p                   = $data->{results}{$instrument}{percentiles};
        my $range_85_percentile = $p->{85};
        $table->addRow($instrument, $direction, $pivot, $atr14, sprintf("%.2f", $range_now), $close,
            sprintf("%.2f",$p->{85}) . " (" . sprintf("%.4f",($pivot > $close ? $pivot-$p->{85}*$atr14:$pivot+$p->{85}*$atr14)) . ")",
            sprintf("%.2f",$p->{90}) . " (" . sprintf("%.4f",($pivot > $close ? $pivot-$p->{90}*$atr14:$pivot+$p->{90}*$atr14)) . ")",
            sprintf("%.2f",$p->{95}) . " (" . sprintf("%.4f",($pivot > $close ? $pivot-$p->{95}*$atr14:$pivot+$p->{95}*$atr14)) . ")");
        print "SIGNAL $direction $instrument\n" if ($range_85_percentile < $range_now);
    }
    print $table;

sub fetch_url {
    my $url = "http://api.fxhistoricaldata.com" . shift;
    my $content = get($url);
    die($!) unless($content);
    return from_json($content);
}
