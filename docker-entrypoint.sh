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
    ln -sf /dev/stdout /var/log/manticore/query.log
  fi

if [ -n "$MCL" ]; then
    export LIB_MANTICORE_COLUMNAR="/var/lib/manticore/columnar/lib_manticore_columnar.so"
    export LIB_MANTICORE_SECONDARY="/var/lib/manticore/columnar/lib_manticore_secondary.so"

   if [[ ! -f "$LIB_MANTICORE_COLUMNAR" && ! -f "$LIB_MANTICORE_SECONDARY" ]]; then
      mkdir /var/lib/manticore/columnar/

      MCL_URL=$(cat /mcl.url)
      wget -P /tmp $MCL_URL

      LAST_PATH=$(pwd)
      cd /tmp
      PACKAGE_NAME=$(ls | grep manticore-columnar | head -n 1)
      ar -x $PACKAGE_NAME
      tar -xf data.tar.gz
      find . -name '*.so' -exec cp {} /var/lib/manticore/columnar/ \;
      cd $LAST_PATH
   fi
fi
}
_main() {
  # first arg is `h` or some `--option`
  if [ "${1#-}" != "$1" ]; then
    set -- searchd "$@"
  fi
  if [ "$1" = 'searchd' ] && ! _searchd_want_help "@"; then
    docker_setup_env "$@"
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
