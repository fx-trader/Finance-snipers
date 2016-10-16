#!/bin/sh

docker run --restart=always --name signal-scan -h signal-scan.fxhistoricaldata.com -v /root/src:/root/src --log-driver=journald -d fxtrader/finance-hostedtrader sh -c 'exec /usr/bin/perl /root/src/signal_check.pl'
