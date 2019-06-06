FROM debian:stretch-slim

RUN groupadd -r manticore && useradd -r -g manticore manticore

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
	&& gosu nobody true \
	&& apt-get purge -y --auto-remove ca-certificates wget

ENV MANTICORE_VERSION 3.0.2
	
RUN set -x \
	\
	&& buildDeps='  ca-certificates wget  \
    default-libmysqlclient-dev \
    libexpat-dev \
    libpq-dev \
    unixodbc-dev \
    flex \
    bison \
    git \
    build-essential \
    libssl-dev \
    libboost-system-dev \
    libboost-program-options-dev \
    ' \
    && apt-get update && apt-get install -y \
    $buildDeps --no-install-recommends  \
    && rm -rf /var/lib/apt/lists/* \
    && cd / && wget https://github.com/Kitware/CMake/releases/download/v3.14.0/cmake-3.14.0-Linux-x86_64.tar.gz \ 
	&& tar zxvf cmake-3.14.0-Linux-x86_64.tar.gz && rm -f cmake-3.14.0-Linux-x86_64.tar.gz && export PATH=$PATH:/cmake-3.14.0-Linux-x86_64/bin \	
	&& cd /tmp && git clone https://github.com/manticoresoftware/manticore.git manticore \
	&& cd manticore && git checkout $MANTICORE_VERSION && mkdir build && cd build \
	&& cd /tmp/manticore/build && cmake \
    -D SPLIT_SYMBOLS=1 \
    -D WITH_MYSQL=ON \
    -D WITH_PGSQL=ON \
    -D WITH_RE2=ON \
    -D WITH_STEMMER=ON \
    -D DISABLE_TESTING=ON \
    -D CMAKE_INSTALL_PREFIX=/ \
    -D CONFFILEDIR=/etc/sphinxsearch \
    -D SPHINX_TAG=release .. \
    && make install \
    && apt-get purge -y --auto-remove $buildDeps ca-certificates wget \
    && apt-get update && apt install -y  libmariadbclient-dev-compat libexpat1 libodbc1 libpq5 openssl \
    && rm -rf /var/lib/apt/lists/* && rm -rf /usr/lib/debug/usr/bin/* && rm -rf /tmp/manticore \
	&& rm -rf /cmake-3.14.0-Linux-x86_64

COPY sphinx.conf /etc/sphinxsearch/
RUN mkdir -p /var/run/manticore && chown -R manticore:manticore /var/run/manticore && chmod 2777 /var/run/manticore \
    && mkdir /var/lib/manticore &&  mkdir /var/lib/manticore/replication &&  mkdir /var/lib/manticore/data &&  mkdir /var/lib/manticore/log && chown -R manticore:manticore /var/lib/manticore && chmod 777 /var/lib/manticore
	

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
VOLUME /var/lib/manticore /etc/sphinxsearch
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
EXPOSE 9315-9325
CMD ["searchd", "--nodetach"]

