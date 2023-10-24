#!/bin/bash
set -eo pipefail

# check to see if this file is being run or sourced from another script
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  [ "${#FUNCNAME[@]}" -ge 2 ] &&
    [ "${FUNCNAME[0]}" = '_is_sourced' ] &&
    [ "${FUNCNAME[1]}" = 'source' ]
}
_searchd_want_help() {
  local arg
  for arg; do
    case "$arg" in
    -'?' | --help | -h | -v)
      return 0
      ;;
    esac
  done
  return 1
}

docker_setup_env() {
  if [ -n "$QUERY_LOG_TO_STDOUT" ]; then
    export searchd_query_log=/var/log/manticore/query.log
    [ ! -f /var/log/manticore/query.log ] && ln -sf /dev/stdout /var/log/manticore/query.log
  fi

  if [[ "${EXTRA}" == "1" ]]; then
    EXTRA_DIR="/var/lib/manticore/.extra/"

    if [ -f "${EXTRA_DIR}manticore-executor" ]; then
      cp ${EXTRA_DIR}manticore-executor /usr/bin/manticore-executor
    fi

    if [ ! -f /etc/ssl/cert.pem ]; then
      for cert in "/etc/ssl/certs/ca-certificates.crt" \
        "/etc/pki/tls/certs/ca-bundle.crt" \
        "/etc/ssl/ca-bundle.pem" \
        "/etc/pki/tls/cacert.pem" \
        "/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"; do
        if [ -f "$cert" ]; then
          ln -s "$cert" /etc/ssl/cert.pem
          break
        fi
      done
    fi

    LAST_PATH=$(pwd)
    EXTRA_URL=$(cat /extra.url)
    EXTRA_INSTALLED_VERSION_PATH="/var/lib/manticore/.extra.installed"
    NEW_EXTRA_VERSION=$(echo $EXTRA_URL | cut -d"_" -f4 | cut -d"-" -f3)

    if [ ! -f $EXTRA_INSTALLED_VERSION_PATH ]; then
      # Extra was never be installed
      echo "Install extra packages"
      install_extra $EXTRA_URL $EXTRA_INSTALLED_VERSION_PATH $NEW_EXTRA_VERSION $EXTRA_DIR
    else
      INSTALLED_EXTRA_VERSION=$(cat $EXTRA_INSTALLED_VERSION_PATH)

      if [[ $INSTALLED_EXTRA_VERSION != $NEW_EXTRA_VERSION ]]; then
        echo "Extra packages version mismatch. Updating..."
        install_extra $EXTRA_URL $EXTRA_INSTALLED_VERSION_PATH $NEW_EXTRA_VERSION $EXTRA_DIR 1
      fi
    fi

    MCL="1"
  fi

  if [[ "${MCL}" == "1" ]]; then
    MCL_DIR="/var/lib/manticore/.mcl/"
    LIB_MANTICORE_COLUMNAR="${MCL_DIR}lib_manticore_columnar.so"
    LIB_MANTICORE_SECONDARY="${MCL_DIR}lib_manticore_secondary.so"
    COLUMNAR_VERSION=$(cat /mcl.url | cut -d"-" -f6 | cut -d"_" -f1)

    [ -L /usr/share/manticore/modules/lib_manticore_columnar.so ] || ln -s $LIB_MANTICORE_COLUMNAR /usr/share/manticore/modules/lib_manticore_columnar.so
    [ -L /usr/share/manticore/modules/lib_manticore_secondary.so ] || ln -s $LIB_MANTICORE_SECONDARY /usr/share/manticore/modules/lib_manticore_secondary.so

    searchd -v | grep -i error | egrep "trying to load" &&
      rm $LIB_MANTICORE_COLUMNAR $LIB_MANTICORE_SECONDARY &&
      echo "WARNING: wrong MCL version was removed, installing the correct one"

    if ! searchd --version | head -n 1 | grep $COLUMNAR_VERSION; then
      echo "Columnar version mismatch"
      rm $LIB_MANTICORE_COLUMNAR > /dev/null 2>&1  || echo "Lib columnar not installed"
      rm $LIB_MANTICORE_SECONDARY > /dev/null 2>&1  || echo "Secondary columnar not installed"
    fi

    if [[ ! -f "$LIB_MANTICORE_COLUMNAR" || ! -f "$LIB_MANTICORE_SECONDARY" ]]; then
      if ! mkdir -p ${MCL_DIR}; then
        echo "ERROR: Manticore Columnar Library is inaccessible: couldn't create ${MCL_DIR}."
        exit
      fi

      MCL_URL=$(cat /mcl.url)
      wget -P /tmp $MCL_URL

      LAST_PATH=$(pwd)
      cd /tmp
      PACKAGE_NAME=$(ls | grep manticore-columnar | head -n 1)
      ar -x $PACKAGE_NAME
      tar -xf data.tar.gz
      find . -name '*.so' -exec cp {} ${MCL_DIR} \;
      cd $LAST_PATH
    fi
  fi

  if [[ -z "${MCL}" && "${MCL}" != "1" ]]; then
    export searchd_secondary_indexes=0
  fi

  if [[ -n ${CREATE_PLAIN_TABLES} && ${CREATE_PLAIN_TABLES} != "1" ]]; then

    INDEXER_TABLES_LIST=""

    IFS=';' read -ra ITM <<<"${CREATE_PLAIN_TABLES}"
    for item in "${ITM[@]}"; do

      IFS=':' read -ra LINE <<<"$item"

      if [ -z "${LINE[1]}" ]; then
        INDEXER_TABLES_LIST+=" ${LINE[0]}"
        continue
      fi

      if [[ ! "${LINE[1]}" =~ ^([0-9,\-\/\*]+ )([0-9,\-\/\*]+ )([0-9,\-\/\*]+ )([0-9,\-\/\*]+ )([0-9,\-\/\*]+)$ ]]; then
        echo -e "\033[0;31mError:\033[0m Wrong crontab syntax \033[0;31m${LINE[1]}\033[0m for table: ${LINE[0]}"
        continue
      fi

      md5=$(echo -n ${LINE[0]} | md5sum | awk '{print $1}')
      echo "${LINE[1]} cd /var/lib/manticore && flock -w 0 /tmp/${md5}.lock indexer --rotate ${LINE[0]} | sed \"s/.*/$(date): Indexer_${LINE[0]}: &/\" >> /proc/1/fd/1" >> /etc/cron.d/manticore
      CRONTAB_AFFECTED=1
    done

    if [ -n "$CRONTAB_AFFECTED" ]; then
        crontab /etc/cron.d/manticore
        cron -f &
    fi

    if [ -n "$INDEXER_TABLES_LIST" ]; then
        indexer $INDEXER_TABLES_LIST
    fi
  fi

  if [[ "${CREATE_PLAIN_TABLES}" == "1" ]]; then
    indexer --all
  fi

}

install_extra() {

  # $EXTRA_URL $1
  # $EXTRA_INSTALLED_VERSION_PATH $2
  # $NEW_EXTRA_VERSION $3
  # $EXTRA_DIR $4
  # $FORCE $5

  # In case force update
  if [ $5=1 ]; then
    rm -rf "${4}"
  fi


  if [ ! -d $4 ]; then
    mkdir $4
  fi

  if [[ -z $(find $4 -name 'manticore-executor') ]]; then
    wget -P $4 $1
    cd $4
    PACKAGE_NAME=$(ls | grep manticore-executor | head -n 1)
    ar -x $PACKAGE_NAME
    tar -xf data.tar.xz
  fi

  find $4 -name 'manticore-executor' -exec cp {} /usr/bin/manticore-executor \;

  echo $3 >$2

  cd $LAST_PATH

  rm -rf "${4}*"
  cp /usr/bin/manticore-executor ${4}
}

_main() {
  # first arg is `h` or some `--option`

  if [ "${1#-}" != "$1" ]; then
    set -- searchd "$@"
  fi

  if ([ "$1" = 'searchd' ] || [ "$1" = 'indexer' ]) && ! _searchd_want_help "@"; then
    # allow the container to be started with `--user`
    if [ "$(id -u)" = '0' ]; then
      find /var/lib/manticore /var/log/manticore /var/run/manticore /etc/manticoresearch /dev/stdout \! -user manticore -exec chown manticore:manticore '{}' +
      exec gosu manticore "$0" "$@"
    fi
  fi

  if ! _searchd_want_help "@"; then
    docker_setup_env "$@"
  fi

  _replace_conf_from_env
  exec "$@"
}

_replace_conf_from_env() {
  # we exit in case a custom config is provided
  if [ "$(md5sum /etc/manticoresearch/manticore.conf | awk '{print $1}')" != "$(cat /manticore.conf.md5)" ]; then return; fi

  sed_query=""

  while IFS='=' read -r oldname value; do
    if [[ $oldname == 'searchd_'* || $oldname == 'common_'* ]]; then
      value=$(echo ${!oldname} | sed 's/\//\\\//g')
      oldname=$(echo $oldname | sed "s/searchd_//g;s/common_//g;")
      newname=$oldname

      if [[ $newname == 'listen' ]]; then
        oldname="listen_env"
        IFS='|' read -ra LISTEN_VALUES <<<"$value"
        count=0

        for i in "${LISTEN_VALUES[@]}"; do
          if [[ $count == 0 ]]; then
            value=$i
          else
            value="$value\n    listen = $i"
          fi
          count=$((count + 1))
        done
      fi

      if [[ -z $sed_query ]]; then
        sed_query="s/(#\s)*?$oldname\s?=\s?.*?$/$newname = $value/g"
      else
        sed_query="$sed_query;s/(#\s)*?$oldname\s?=\s?.*?$/$newname = $value/g"
      fi

    fi
  done < <(env)

  if [[ ! -z $sed_query ]]; then
    sed -i -E "$sed_query" /etc/manticoresearch/manticore.conf
  fi
}
# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
  _main "$@"
fi
