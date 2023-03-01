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
    if [[ $(du /usr/bin/manticore-executor | cut -f1) == "0" ]]; then
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
            EXTRA_DIR="/var/lib/manticore/.extra/"

            if [ ! -d $EXTRA_DIR ]; then
              mkdir $EXTRA_DIR
            fi

            if [[ -z $(find $EXTRA_DIR -name 'manticore-executor') ]]; then
                wget -P $EXTRA_DIR $EXTRA_URL
                cd $EXTRA_DIR
                PACKAGE_NAME=$(ls | grep manticore-executor | head -n 1)
                ar -x $PACKAGE_NAME
                tar -xf data.tar.xz
            fi

            find $EXTRA_DIR -name 'manticore-executor' -exec cp {} /usr/bin/manticore-executor \;
            cd $LAST_PATH
    fi

    MCL="1"
  fi

  if [[ "${MCL}" == "1" ]]; then
      LIB_MANTICORE_COLUMNAR="/var/lib/manticore/.mcl/lib_manticore_columnar.so"
      LIB_MANTICORE_SECONDARY="/var/lib/manticore/.mcl/lib_manticore_secondary.so"

      [ -L /usr/share/manticore/modules/lib_manticore_columnar.so ] || ln -s $LIB_MANTICORE_COLUMNAR /usr/share/manticore/modules/lib_manticore_columnar.so
      [ -L /usr/share/manticore/modules/lib_manticore_secondary.so ] || ln -s $LIB_MANTICORE_SECONDARY /usr/share/manticore/modules/lib_manticore_secondary.so

      searchd -v|grep -i error|egrep "trying to load" \
      && rm $LIB_MANTICORE_COLUMNAR $LIB_MANTICORE_SECONDARY \
      && echo "WARNING: wrong MCL version was removed, installing the correct one"

      if [[ ! -f "$LIB_MANTICORE_COLUMNAR" || ! -f "$LIB_MANTICORE_SECONDARY" ]]; then
        if ! mkdir -p /var/lib/manticore/.mcl/ ; then
          echo "ERROR: Manticore Columnar Library is inaccessible: couldn't create /var/lib/manticore/.mcl/."
          exit
        fi

        MCL_URL=$(cat /mcl.url)
        wget -P /tmp $MCL_URL

        LAST_PATH=$(pwd)
        cd /tmp
        PACKAGE_NAME=$(ls | grep manticore-columnar | head -n 1)
        ar -x $PACKAGE_NAME
        tar -xf data.tar.gz
        find . -name '*.so' -exec cp {} /var/lib/manticore/.mcl/ \;
        cd $LAST_PATH
      fi
  fi


  if [[ -z "${MCL}" && "${MCL}" != "1" ]]; then
    export searchd_secondary_indexes=0
  fi

}
_main() {
  # first arg is `h` or some `--option`
  if [ "${1#-}" != "$1" ]; then
    set -- searchd "$@"
  fi

  if ! _searchd_want_help "@"; then
    docker_setup_env "$@"
  fi

  if ([ "$1" = 'searchd' ] || [ "$1" = 'indexer' ]) && ! _searchd_want_help "@"; then
    # allow the container to be started with `--user`
    if [ "$(id -u)" = '0' ]; then
      find /var/lib/manticore /var/log/manticore /var/run/manticore /etc/manticoresearch \! -user manticore -exec chown manticore '{}' +
      exec gosu manticore "$0" "$@"
    fi
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
        IFS='|' read -ra ADDR <<<"$value"
        count=0

        for i in "${ADDR[@]}"; do
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
