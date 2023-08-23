FROM ubuntu:jammy as initial

ARG TARGETPLATFORM

ARG DEV
ARG DAEMON_URL
ARG MCL_URL
ARG DEBIAN_FRONTEND=noninteractive

RUN groupadd -r manticore && useradd -r -g manticore manticore

ENV GOSU_VERSION 1.11

ENV MCL_URL=${MCL_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-columnar-lib_2.2.4-230822-5aec342__ARCH_64.deb"}
ENV DAEMON_URL=${DAEMON_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-server_6.2.12-230822-dc5144d35__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-server-core_6.2.12-230822-dc5144d35__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-backup_1.0.8-23080408-f7638f9_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-buddy_1.0.18-23080408-2befdbe_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-tools_6.2.12-230822-dc5144d35__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-common_6.2.12-230822-dc5144d35_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore_6.2.12-230822-dc5144d35__ARCH_64.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-dev_6.2.12-230822-dc5144d35_all.deb \
https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-icudata-65l.deb"}

# If you set EXTRA=1, MCL=1 will automatically be invoked.
# We're only providing the executor URL here because the columnar-lib included in the package will be installed via the MCL=1 flag.
ENV EXTRA_URL=${EXTRA_URL:-"https://repo.manticoresearch.com/repository/manticoresearch_jammy/dists/jammy/main/binary-_ARCH_64/manticore-executor_0.7.8-23082210-810d7d3__ARCH_64.deb"}

RUN if [ -z "$MCL_URL" ] ; then \
    echo "WARNING: MCL_URL is empty"; \
elif [ ! -z "${MCL_URL##*_ARCH_*}" ] ; then \
    echo "ERROR: MCL_URL is not empty, but no _ARCH_ placeholder found in daemon URL"; \
    exit 1; \
fi

RUN if [ -z "$DAEMON_URL" ] ; then \
    echo "WARNING: DAEMON_URL is empty"; \
elif [ ! -z "${DAEMON_URL##*_ARCH_*}" ] ; then \
    echo "ERROR: DAEMON_URL is not empty, but no _ARCH_ placeholder found in daemon URL"; \
    exit 1; \
fi

RUN set -x \
    && if [ "$TARGETPLATFORM" = "linux/arm64" ] ; then export ARCH="arm"; else export ARCH="amd"; fi \
    && echo "Start building image for linux/${ARCH}64 architecture" \
    && mkdir /etc/ssl/ && touch /usr/bin/manticore-executor \
    && chown -R manticore:manticore /usr/bin/manticore-executor /etc/ssl/ \
    && chmod +x /usr/bin/manticore-executor \
    && apt-get -y update && apt-get -y install --no-install-recommends ca-certificates binutils wget gnupg xz-utils dirmngr locales && rm -rf /var/lib/apt/lists/* \
    && locale-gen --lang en_US \
    && wget -q -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && wget -q -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
    && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    && apt-get update && apt-get -y install libexpat1 libodbc1 libpq5 openssl libcurl4 libcrypto++8 libmysqlclient21 mysql-client \
    && apt-get -y purge --auto-remove \
    && rm -f /usr/bin/mariabackup /usr/bin/mysqlslap /usr/bin/mysqladmin /usr/bin/mysqlimport  \
    /usr/bin/mysqlshow /usr/bin/mbstream /usr/bin/mysql_waitpid /usr/bin/innotop /usr/bin/mysqlaccess /usr/bin/mytop  \
    /usr/bin/mysqlreport /usr/bin/mysqldumpslow /usr/bin/mysql_find_rows /usr/bin/mysql_fix_extensions  \
    /usr/bin/mysql_embedded /usr/bin/mysqlcheck

# The below is to make sure the following is never taken from cache
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache

# Add any .deb or .ddeb packages in the current dir to install them all later
ADD *deb /packages/

RUN if [ "$TARGETPLATFORM" = "linux/arm64" ] ; then export ARCH="arm"; else export ARCH="amd"; fi \
    && if [ "${DEV}" = "1" ]; then \
      echo "2nd step of building dev image for linux/${ARCH}64 architecture" \
      && wget -q https://repo.manticoresearch.com/manticore-dev-repo.noarch.deb \
      && dpkg -i manticore-dev-repo.noarch.deb \
      && apt-key adv --fetch-keys 'https://repo.manticoresearch.com/GPG-KEY-manticore' && apt-get -y update && apt-get -y install manticore \
      && apt-get -y update  \
      && echo $(apt-get -y download --print-uris manticore-columnar-lib | cut -d" " -f1 | cut -d "'" -f 2) > /mcl.url \
      && echo $(apt-get -y download --print-uris manticore-executor | cut -d" " -f1 | cut -d "'" -f 2) > /extra.url ;\
    elif [ ! -z "$DAEMON_URL" ]; then \
      echo "2nd step of building release image for linux/${ARCH}64 architecture" \
      && echo "ARCH: ${ARCH}" \
      && echo $DAEMON_URL | sed "s/_ARCH_/$ARCH/g" \
      && wget -q $(echo $DAEMON_URL | sed "s/_ARCH_/$ARCH/g") \
      && apt-get -y install ./manticore*deb \
      && echo $MCL_URL | sed "s/_ARCH_/$ARCH/g" > /mcl.url \
      && echo $EXTRA_URL | sed "s/_ARCH_/$ARCH/g" > /extra.url \
      && rm *.deb ; \
    fi
RUN if [ -d "/packages/" ]; then apt -y install /packages/*deb; fi \
    && mkdir -p /var/run/manticore \
    && mkdir -p /var/lib/manticore/replication \
    && apt-get -y purge --auto-remove \
    && rm -rf /var/lib/apt/lists/* \
    && rm -fr /packages \
    && rm -f /usr/bin/spelldump /usr/bin/wordbreaker \
    && mkdir -p /var/run/mysqld/ \
    && chown manticore:manticore /var/lib/manticore/ /var/run/mysqld/ /usr/share/manticore/modules/ /var/run/manticore \
    && echo "\n[mysql]\nsilent\nwait\ntable\n" >> /etc/mysql/my.cnf \
    && wget -q https://repo.manticoresearch.com/repository/morphology/en.pak.tgz?docker_build=1 -O /tmp/en.pak.tgz \
    && wget -q https://repo.manticoresearch.com/repository/morphology/de.pak.tgz?docker_build=1 -O /tmp/de.pak.tgz \
    && wget -q https://repo.manticoresearch.com/repository/morphology/ru.pak.tgz?docker_build=1 -O /tmp/ru.pak.tgz \
    && tar -xf /tmp/en.pak.tgz -C /usr/share/manticore/ \
    && tar -xf /tmp/de.pak.tgz -C /usr/share/manticore/ \
    && tar -xf /tmp/ru.pak.tgz -C /usr/share/manticore/

COPY manticore.conf /etc/manticoresearch/
RUN md5sum /etc/manticoresearch/manticore.conf|awk '{print $1}' > /manticore.conf.md5
COPY sandbox.sql /sandbox.sql
COPY .mysql_history /root/.mysql_history

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh

FROM scratch
COPY --from=initial / /
WORKDIR /var/lib/manticore
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
CMD ["searchd", "--nodetach"]

# How to build manually:
#   Prepare builder:
#     docker buildx create --use
#
#   Dev version:
#     Build and load to local registry:
#       docker buildx build --progress=plain --build-arg DEV=1 --load --platform linux/amd64 --tag manticore:dev .
#     Build multi-arch and push to remote registry:
#       docker buildx build --progress=plain --build-arg DEV=1 --push --platform linux/amd64,linux/arm64 --tag username/manticore:dev .
#   Release version:
#     docker buildx build --progress=plain --build-arg --push --platform linux/amd64,linux/arm64 --tag username/manticore:dev .
#
#   With empty urls assuming *deb in the local dir:
#     docker buildx build --progress=plain --build-arg DEV=0 --build-arg DAEMON_URL="" --build-arg  MCL_URL="" --load --platform linux/amd64 --tag username/manticore:local .
