#!/bin/sh

SNIPER_DIR=/root/src/Finance-snipers

docker run  \
    --restart=always \
    --name signal-scan \
    --link signal-scan-redis:signal-scan-redis
    -h signal-scan.fxhistoricaldata.com \
    -v $SNIPER_DIR/bin:/root/snipers \
    --log-driver=json-file \
    -d fxtrader/finance-hostedtrader \
    sh -c 'exec /usr/bin/perl /root/snipers/signal_check.pl'
