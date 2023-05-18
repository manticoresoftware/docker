FROM ubuntu:focal

ARG TARGETPLATFORM

ARG DEV
ARG DAEMON_URL
ARG MCL_URL
ARG DEBIAN_FRONTEND=noninteractive

RUN groupadd -r manticore && useradd -r -g manticore manticore

ENV GOSU_VERSION 1.11

ENV MCL_URL=${MCL_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-columnar-lib_2.0.4-230306-5a49bd7__ARCH_64.deb"}
ENV DAEMON_URL=${DAEMON_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-server_6.0.4-230314-1a3a4ea82__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-server-core_6.0.4-230314-1a3a4ea82__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-backup_0.5.2-23020607-4a37932_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-buddy_0.4.2-23031500-36757ee_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-tools_6.0.4-230314-1a3a4ea82__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-common_6.0.4-230314-1a3a4ea82_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore_6.0.4-230314-1a3a4ea82__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-dev_6.0.4-230314-1a3a4ea82_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-icudata-65l.deb"}

# if you set EXTRA=1, MCL=1 will called automatically
# Here is only executor URL, cause columnar-lib which included into package will be installed via MCL=1 flag.
ENV EXTRA_URL=${EXTRA_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_focal/dists/focal/main/binary-_ARCH_64/manticore-executor_0.6.2-23012605-d95e43e__ARCH_64.deb"}

RUN if [ ! -z "${MCL_URL##*_ARCH_*}" ] ; then echo No _ARCH_ placeholder in daemon URL && exit 1 ; fi
RUN if [ ! -z "${DAEMON_URL##*_ARCH_*}" ] ; then echo No _ARCH_ placeholder in daemon URL && exit 1 ; fi

RUN set -x \
    && if [ "$TARGETPLATFORM" = "linux/arm64" ] ; then export ARCH="arm"; else export ARCH="amd"; fi \
    && echo "Start building image for linux/${ARCH}64 architecture" \
    && mkdir /etc/ssl/ && touch /usr/bin/manticore-executor \
    && chown -R manticore:manticore /usr/bin/manticore-executor /etc/ssl/ \
    && chmod +x /usr/bin/manticore-executor \
    && apt-get -y update && apt-get -y install --no-install-recommends ca-certificates binutils wget gnupg xz-utils dirmngr locales && rm -rf /var/lib/apt/lists/* \
    && locale-gen --lang en_US \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
    && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    && apt-get update && apt-get -y install libexpat1 libodbc1 libpq5 openssl libcurl4 libcrypto++6 libmysqlclient21 mysql-client \
    && apt-get -y purge --auto-remove \
    && rm -f /usr/bin/mariabackup /usr/bin/mysqlslap /usr/bin/mysqladmin /usr/bin/mysqlimport  \
    /usr/bin/mysqlshow /usr/bin/mbstream /usr/bin/mysql_waitpid /usr/bin/innotop /usr/bin/mysqlaccess /usr/bin/mytop  \
    /usr/bin/mysqlreport /usr/bin/mysqldumpslow /usr/bin/mysql_find_rows /usr/bin/mysql_fix_extensions  \
    /usr/bin/mysql_embedded /usr/bin/mysqlcheck

# The below is to make sure the following is never taken from cache
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache

RUN if [ "$TARGETPLATFORM" = "linux/arm64" ] ; then export ARCH="arm"; else export ARCH="amd"; fi \
    && if [ "${DEV}" = "1" ]; then \
      echo "2nd step of building dev image for linux/${ARCH}64 architecture" \
      && wget https://repo.manticoresearch.com/manticore-dev-repo.noarch.deb \
      && dpkg -i manticore-dev-repo.noarch.deb \
      && apt-key adv --fetch-keys 'https://repo.manticoresearch.com/GPG-KEY-manticore' && apt-get -y update && apt-get -y install manticore \
      && apt-get -y update  \
      && echo $(apt-get -y download --print-uris manticore-columnar-lib | cut -d" " -f1 | cut -d "'" -f 2) > /mcl.url \
      && echo $(apt-get -y download --print-uris manticore-executor | cut -d" " -f1 | cut -d "'" -f 2) > /extra.url ;\
    else \
      echo "2nd step of building release image for linux/${ARCH}64 architecture" \
      && wget $(echo $DAEMON_URL | sed "s/_ARCH_/$ARCH/g") \
      && apt-get -y install ./manticore*deb \
      && echo $MCL_URL | sed "s/_ARCH_/$ARCH/g" > /mcl.url \
      && echo $EXTRA_URL | sed "s/_ARCH_/$ARCH/g" > /extra.url \
      && rm *.deb ; \
    fi \
    && mkdir -p /var/run/manticore \
    && mkdir -p /var/lib/manticore/replication \
    && apt-get -y purge --auto-remove \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/bin/spelldump /usr/bin/wordbreaker \
    && mkdir -p /var/run/mysqld/ \
    && chown manticore:manticore /var/lib/manticore/ /var/run/mysqld/ /usr/share/manticore/modules/ /var/run/manticore \
    && echo "\n[mysql]\nsilent\nwait\ntable\n" >> /etc/mysql/my.cnf \
    && wget -P /tmp https://repo.manticoresearch.com/repository/morphology/en.pak.tgz \
    && wget -P /tmp https://repo.manticoresearch.com/repository/morphology/de.pak.tgz \
    && wget -P /tmp https://repo.manticoresearch.com/repository/morphology/ru.pak.tgz \
    && tar -xf /tmp/en.pak.tgz -C /usr/share/manticore/ \
    && tar -xf /tmp/de.pak.tgz -C /usr/share/manticore/ \
    && tar -xf /tmp/ru.pak.tgz -C /usr/share/manticore/

COPY manticore.conf /etc/manticoresearch/
RUN md5sum /etc/manticoresearch/manticore.conf|awk '{print $1}' > /manticore.conf.md5
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
