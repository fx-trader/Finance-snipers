#!/bin/bash

set -euo pipefail

SNIPER_DIR=/root/src/Finance-snipers
cd $SNIPER_DIR
#git pull origin master

    SNIPER_ID=sniper-client
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
            --log-driver=json-file \
            -d fxtrader/finance-hostedtrader sh -c 'exec /usr/bin/perl /root/snipers/sniper-client.pl'
