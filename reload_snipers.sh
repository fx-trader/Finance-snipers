#!/bin/bash

set -euo pipefail

. ~/fxcm.real

SNIPER_DIR=/root/src/Finance-snipers
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
            -h ${SNIPER_ID}.fxhistoricaldata.com \
            -v /root/fx/cfg:/etc/fxtrader \
            -v $SNIPER_DIR/bin:/root/snipers \
            -e FXCM_USERNAME -e FXCM_PASSWORD -e FXCM_ACCOUNT_TYPE \
            -e SYMBOL -e FXCM_SYMBOL \
            -e MAX_EXPOSURE -e EXPOSURE_INCREMENT -e DIRECTION \
            --log-driver=json-file \
            -d fxtrader/finance-hostedtrader sh -c 'exec /usr/bin/perl /root/snipers/fx-sniper.pl'
}

SYMBOL=USDOLLAR FXCM_SYMBOL='USDOLLAR' \
MAX_EXPOSURE=5 EXPOSURE_INCREMENT=1 DIRECTION=long \
load_sniper

#FXCM_USERNAME=GBD118836001 FXCM_PASSWORD='5358' FXCM_ACCOUNT_TYPE=Demo \
