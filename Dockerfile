FROM ubuntu:bionic as builder

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y \
    libmysqlclient-dev \
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
&& rm -rf /var/lib/apt/lists/*

# add cmake as separate layer
# file taken from https://github.com/Kitware/CMake/releases/download/v3.14.0/cmake-3.14.0-Linux-x86_64.tar.gz
ADD cmake-3.14.0-Linux-x86_64.tar.gz /
ENV PATH $PATH:/cmake-3.14.0-Linux-x86_64/bin


RUN cd /tmp && git clone https://github.com/manticoresoftware/manticore.git manticore \
&& cd manticore && git checkout master && mkdir build && cd build


RUN cd /tmp/manticore/build && cmake \
    -D SPLIT_SYMBOLS=1 \
    -D WITH_MYSQL=ON \
    -D WITH_PGSQL=ON \
    -D WITH_RE2=ON \
    -D WITH_STEMMER=ON \
    -D DISABLE_TESTING=ON \
    -D CMAKE_INSTALL_PREFIX=/ \
    -D CONFFILEDIR=/etc/manticoresearch \
    -D SPHINX_TAG=release .. \
&& make -j4 install


FROM ubuntu:bionic
RUN apt-get update && apt-get install -y libexpat1 libodbc1 libpq5 openssl libcrypto++6  libmysqlclient20 libicu60


COPY --from=builder /usr/bin/indexer /usr/bin/
COPY --from=builder /usr/bin/indextool /usr/bin/
COPY --from=builder /usr/bin/searchd /usr/bin/
COPY --from=builder /usr/lib/libgalera_manticore.so.31 /usr/lib/

RUN cd /var/lib/ && mkdir -p manticore/replication && mkdir -p manticore/log && mkdir manticore/data 

COPY manticore.conf /etc/manticoresearch/manticore.conf

VOLUME /var/lib/manticore /etc/manticoresearch
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
EXPOSE 9315-9325
CMD ["/usr/bin/searchd", "--nodetach"]

