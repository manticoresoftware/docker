FROM debian:buster-slim

RUN groupadd -r manticore && useradd -r -g manticore manticore

ENV GOSU_VERSION 1.11
ENV MANTICORE_VERSION 3.4.2

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
        && wget  https://github.com/manticoresoftware/manticoresearch/releases/download/3.4.2/manticore_3.4.2-200410-69033058-release.buster_amd64-bin.deb \
        && dpkg -i manticore_3.4.2-200410-69033058-release.buster_amd64-bin.deb \
        && mkdir -p /var/run/manticore && mkdir -p /var/lib/manticore/replication \
        && apt-get purge -y --auto-remove ca-certificates wget \
        && apt-get update && apt install -y libmariadbclient-dev-compat libexpat1 libodbc1 libpq5 openssl libcrypto++6 mariadb-client \
        && rm -rf /var/lib/apt/lists/*  &&  rm -f manticore_3.4.2-200410-69033058-release.stretch_amd64-bin.deb \
        && rm -f /usr/bin/mariabackup /usr/bin/mysqldump /usr/bin/mysqlslap /usr/bin/mysqladmin /usr/bin/mysqlimport /usr/bin/mysqlshow /usr/bin/mbstream /usr/bin/mysql_waitpid /usr/bin/innotop /usr/bin/mysqlaccess /usr/bin/mytop /usr/bin/mysqlreport /usr/bin/mysqldumpslow /usr/bin/mysql_find_rows /usr/bin/mysql_fix_extensions /usr/bin/mysql_embedded /usr/bin/mysqlcheck \
        && rm -f /usr/bin/spelldump /usr/bin/wordbreaker \
        && mkdir -p /var/run/mysqld/ && chown manticore:manticore /var/run/mysqld/ \
        && echo "\n[mysql]\nsilent\nwait\ntable\n" >> /etc/mysql/my.cnf 

RUN \
    apt update && apt install -y wget \
    && wget http://security.debian.org/debian-security/pool/updates/main/o/openssl/libssl1.0.0_1.0.1t-1+deb8u12_amd64.deb \
    && dpkg --force-all -i libssl1.0.0_1.0.1t-1+deb8u12_amd64.deb \
    && wget https://downloads.mariadb.com/Connectors/c/connector-c-3.1.7/mariadb-connector-c-3.1.7-linux-x86_64.tar.gz \
    && tar zxvf mariadb-connector-c-3.1.7-linux-x86_64.tar.gz \
    && cp mariadb-connector-c-3.1.7-linux-x86_64/lib/mariadb/plugin/caching_sha2_password.so /usr/lib/x86_64-linux-gnu/mariadb19/plugin/ \
    && rm -rf mariadb-connector-c-3.1.7-linux-x86_64.tar.gz mariadb-connector-c-3.1.7-linux-x86_64/ libssl1.0.0_1.0.1t-1+deb8u12_amd64.deb

COPY manticore.conf /etc/manticoresearch/
COPY sandbox.sql /sandbox.sql
COPY .mysql_history /root/.mysql_history

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh
WORKDIR /var/lib/manticore
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
EXPOSE 9315-9325
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
CMD ["searchd", "--nodetach"]
