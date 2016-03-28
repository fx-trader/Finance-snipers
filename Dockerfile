FROM fxtrader/scripts
MAINTAINER Joao Costa <joaocosta@zonalivre.org>

ADD bin bin

CMD /root/bin/fx-sniper.pl
