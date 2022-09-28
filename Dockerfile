FROM ubuntu:focal

ARG DEV
ARG DAEMON_URL
ARG MCL_URL

RUN groupadd -r manticore && useradd -r -g manticore manticore

ENV GOSU_VERSION 1.11
ENV MCL_URL=${MCL_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-amd64/manticore-columnar-lib_1.15.4-220522-2fef34e_amd64.deb"}
ENV DAEMON_URL=${DAEMON_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/manticore_5.0.2-220530-348514c86_amd64.tgz"}

RUN set -x \
    && apt-get update && apt-get -y install --no-install-recommends ca-certificates binutils wget gnupg dirmngr && rm -rf /var/lib/apt/lists/* \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
    && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true && \
    if [ "${DEV}" = "1" ]; then \
      wget https://repo.manticoresearch.com/manticore-dev-repo.noarch.deb \
      && dpkg -i manticore-dev-repo.noarch.deb \
      && apt-key adv --fetch-keys 'https://repo.manticoresearch.com/GPG-KEY-manticore' && apt-get -y update && apt-get -y install manticore \
      && apt-get update  \
      && echo $(apt-get -y download --print-uris manticore-columnar-lib | cut -d" " -f1 | cut -d "'" -f 2) > /mcl.url ;\
    else \
      wget $DAEMON_URL && ARCHIVE_NAME=$(ls | grep '.tgz' | head -n1 ) && tar -xf $ARCHIVE_NAME && rm $ARCHIVE_NAME && \
      dpkg -i manticore* && echo $MCL_URL > /mcl.url && rm *.deb ; \
    fi \
    && mkdir -p /var/run/manticore && mkdir -p /var/lib/manticore/replication \
    && apt-get update && apt-get -y install  libexpat1 libodbc1 libpq5 openssl libcrypto++6 libmysqlclient21 mysql-client \
    && apt-get -y purge --auto-remove \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/bin/mariabackup /usr/bin/mysqldump /usr/bin/mysqlslap /usr/bin/mysqladmin /usr/bin/mysqlimport  \
    /usr/bin/mysqlshow /usr/bin/mbstream /usr/bin/mysql_waitpid /usr/bin/innotop /usr/bin/mysqlaccess /usr/bin/mytop  \
    /usr/bin/mysqlreport /usr/bin/mysqldumpslow /usr/bin/mysql_find_rows /usr/bin/mysql_fix_extensions  \
    /usr/bin/mysql_embedded /usr/bin/mysqlcheck \
    && rm -f /usr/bin/spelldump /usr/bin/wordbreaker \
    && mkdir -p /var/run/mysqld/ && chown manticore:manticore /var/lib/manticore/ /var/run/mysqld/ /usr/share/manticore/modules/ /var/run/manticore \
    && echo "\n[mysql]\nsilent\nwait\ntable\n" >> /etc/mysql/my.cnf && \
    wget -P /tmp https://repo.manticoresearch.com/repository/morphology/en.pak.tgz && \
    wget -P /tmp https://repo.manticoresearch.com/repository/morphology/de.pak.tgz && \
    wget -P /tmp https://repo.manticoresearch.com/repository/morphology/ru.pak.tgz && \
    tar -xf /tmp/en.pak.tgz -C /usr/share/manticore/ &&  \
    tar -xf /tmp/de.pak.tgz -C /usr/share/manticore/ &&  \
    tar -xf /tmp/ru.pak.tgz -C /usr/share/manticore/


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
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
CMD ["searchd", "--nodetach"]
