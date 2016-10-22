#!/bin/bash

set -euo pipefail

. ~/fxcm.real

SNIPER_DIR=`pwd -P`
cd $SNIPER_DIR
#git pull origin master

function load_sniper {
    SNIPER_ID=sniper-${SYMBOL}-${DIRECTION}
    SNIPER_CONTAINER_ID=$(docker ps -a -q -f name=${SNIPER_ID})
    if [ "$SNIPER_CONTAINER_ID" != "" ]; then
        docker rm -f ${SNIPER_ID}
    fi
    docker run \
            --restart=always \
            --name ${SNIPER_ID} \
            --link fxdata \
            -h ${SNIPER_ID}.fxhistoricaldata.com \
            -v /root/fxtrader.cfg:/etc/fxtrader \
            -v $SNIPER_DIR/bin:/root/snipers \
            -e FXCM_USERNAME -e FXCM_PASSWORD -e FXCM_ACCOUNT_TYPE \
            -e SYMBOL -e FXCM_SYMBOL \
            -e MAX_EXPOSURE -e EXPOSURE_INCREMENT -e DIRECTION \
            --log-driver=journald \
            -d fxtrader/finance-hostedtrader sh -c 'exec /usr/bin/perl /root/snipers/fx-sniper.pl'
}

SYMBOL=EURGBP FXCM_SYMBOL='EUR/GBP' \
MAX_EXPOSURE=60000 EXPOSURE_INCREMENT=1000 DIRECTION=short \
load_sniper

SYMBOL=AUDUSD FXCM_SYMBOL='AUD/USD' \
MAX_EXPOSURE=30000 EXPOSURE_INCREMENT=3000 DIRECTION=short \
load_sniper


#FXCM_USERNAME=GBD118836001 FXCM_PASSWORD='5358' FXCM_ACCOUNT_TYPE=Demo \
