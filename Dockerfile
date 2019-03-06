FROM alpine:3.6 as builder

RUN apk add --no-cache \
    git \
    cmake \
    make \
    g++ \
    bison \
    flex \
    mariadb-dev \
    postgresql-dev \
    expat-dev \
    mariadb-client
RUN mkdir /build && cd /build \
&& git clone https://github.com/manticoresoftware/manticore.git  \
&& cd manticore && git checkout manticore-2.8.1 \
&& mkdir -p build && cd build \
&& cmake \
    -D SPLIT_SYMBOLS=1 \
    -D WITH_MYSQL=ON \
    -D WITH_PGSQL=ON \
    -D WITH_RE2=ON \
    -D WITH_STEMMER=ON \
    -D DISABLE_TESTING=ON \
    -D CMAKE_INSTALL_PREFIX=/usr \
    -D CONFFILEDIR=/etc/sphinxsearch \
    -D SPHINX_TAG=release .. \
&& make -j4 searchd indexer indextool
COPY sphinx.conf /build/manticore/build/src/
FROM alpine:3.6
RUN apk add --no-cache \
    mariadb-libs \
    mariadb-client-libs \
    postgresql-libs \
    expat \
&& mkdir -p /var/lib/manticore/log && mkdir -p /var/lib/manticore/data/
COPY --from=builder /build/manticore/build/src/indexer /usr/bin/
COPY --from=builder /build/manticore/build/src/indextool /usr/bin/
COPY --from=builder /build/manticore/build/src/searchd /usr/bin/
COPY --from=builder /build/manticore/build/src/sphinx.conf /etc/sphinxsearch/sphinx.conf
VOLUME /var/lib/manticore /etc/sphinxsearch
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
CMD [ "/usr/bin/searchd", "--nodetach" ]

