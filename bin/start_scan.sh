#!/bin/sh

SNIPER_DIR=`pwd -P`

docker run  \
    --restart=always \
    --name signal-scan \
    -h signal-scan.fxhistoricaldata.com \
    -v $SNIPER_DIR/bin:/root/snipers \
    --log-driver=journald \
    -d fxtrader/finance-hostedtrader \
    sh -c 'exec /usr/bin/perl /root/snipers/signal_check.pl'
