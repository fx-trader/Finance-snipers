#!/bin/bash

set -euo pipefail

. ~/fxcm.real

cd /root/Finance-snipers
git pull origin master

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
            -v /root/Finance-snipers/bin:/root/snipers \
            -e FXCM_USERNAME -e FXCM_PASSWORD -e FXCM_ACCOUNT_TYPE \
            -e SYMBOL -e FXCM_SYMBOL \
            -e MAX_EXPOSURE -e EXPOSURE_INCREMENT -e DIRECTION \
            --log-driver=journald \
            -d fxtrader/scripts sh -c 'exec /usr/bin/perl /root/snipers/fx-sniper.pl'
}

SYMBOL=XAGUSD FXCM_SYMBOL='XAG/USD' \
MAX_EXPOSURE=2100 EXPOSURE_INCREMENT=50 DIRECTION=long \
load_sniper

#SYMBOL=XAGUSD FXCM_SYMBOL='XAG/USD' \
#MAX_EXPOSURE=300 EXPOSURE_INCREMENT=50 DIRECTION=long \
#load_sniper


#FXCM_USERNAME=GBD118836001 FXCM_PASSWORD='5358' FXCM_ACCOUNT_TYPE=Demo \
