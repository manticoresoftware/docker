FROM debian:stretch-slim

ENV GOSU_VERSION 1.11
RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates wget gnupg dirmngr && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
	&& gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
	&& { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
	&& rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& gosu nobody true 
	
ENV MANTICORE_VERSION 3.2.2
	
RUN  wget  https://github.com/manticoresoftware/manticoresearch/releases/download/3.2.2/manticore_3.2.2-191226-afd60463-release.stretch_amd64-bin.deb \
    && dpkg -i manticore_3.2.2-191226-afd60463-release.stretch_amd64-bin.deb \
    && mkdir -p /var/run/manticore && mkdir -p /var/lib/manticore/replication \
    && apt-get purge -y --auto-remove ca-certificates wget \
    && apt-get update && apt install -y  libmariadbclient-dev-compat libexpat1 libodbc1 libpq5 openssl libcrypto++6\
    && rm -rf /var/lib/apt/lists/*  &&  rm -f manticore_3.2.2-191226-afd60463-release.stretch_amd64-bin.deb

COPY manticore.conf /etc/manticoresearch/

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
VOLUME /var/lib/manticore /etc/manticoresearch /var/log/manticore
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
EXPOSE 9315-9325
CMD ["searchd", "--nodetach"]

