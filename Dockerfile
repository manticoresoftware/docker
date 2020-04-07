FROM debian:stretch-slim as builder

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y \
     libmariadbclient-dev-compat  \
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

RUN cd /tmp/manticore/build && cmake -D DISTR_BUILD=bionic .. && make -j4 package

RUN find . -type f -name '*-bin.deb' -exec sh -c 'x="{}"; mv "$x" manticore_latest.deb' \;

FROM debian:stretch-slim
RUN apt-get update && apt-get install -y libmariadbclient-dev-compat libexpat1 libodbc1 libpq5 openssl libcrypto++6

COPY --from=builder /manticore_latest.deb manticore_latest.deb

RUN  dpkg -i manticore_latest.deb && rm -rf manticore_latest.deb
RUN mkdir -p /var/run/manticore
COPY manticore.conf /etc/manticoresearch/

EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
EXPOSE 9315-9325
CMD ["/usr/bin/searchd", "--nodetach"]

