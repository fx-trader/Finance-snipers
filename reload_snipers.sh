#!/bin/bash

set -euo pipefail

SNIPER_DIR=/root/src/Finance-snipers
cd $SNIPER_DIR
#git pull origin master

function load_sniper {
    SNIPER_ID=sniper-${INSTRUMENT}-${DIRECTION}
    SNIPER_CONTAINER_ID=$(docker ps -a -q -f name=${SNIPER_ID})
    if [ "$SNIPER_CONTAINER_ID" != "" ]; then
        docker rm -f ${SNIPER_ID}
    fi
    docker run \
            --restart=always \
            --name ${SNIPER_ID} \
            --link smtp:smtp \
            -h ${SNIPER_ID}.fxhistoricaldata.com \
            -v /root/fx/cfg:/etc/fxtrader \
            -v $SNIPER_DIR/bin:/root/snipers \
            -e INSTRUMENT \
            -e MAX_EXPOSURE -e EXPOSURE_INCREMENT -e DIRECTION \
            --log-driver=json-file \
            -d fxtrader/finance-hostedtrader sh -c 'exec /usr/bin/perl /root/snipers/fx-sniper.pl'
}

INSTRUMENT=EUR_GBP \
MAX_EXPOSURE=50000 \
EXPOSURE_INCREMENT=5000 DIRECTION=short \
load_sniper

INSTRUMENT=XAG_USD \
MAX_EXPOSURE=100000 \
EXPOSURE_INCREMENT=10000 DIRECTION=long \
load_sniper
