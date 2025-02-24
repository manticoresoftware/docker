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

  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m' # No Color

  if [ -n "$QUERY_LOG_TO_STDOUT" ]; then
    export searchd_query_log=/var/log/manticore/query.log
    [ ! -f /var/log/manticore/query.log ] && ln -sf /dev/stdout /var/log/manticore/query.log
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
        echo -e "${RED}Error:${NC} Wrong crontab syntax ${RED}${LINE[1]}${NC} for table: ${LINE[0]}"
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

  BACKUP_INIT_FOLDER="/docker-entrypoint-initdb.d"

  if [ -f "${BACKUP_INIT_FOLDER}/versions.json" ]; then
    if [ -f /var/lib/manticore/manticore.json ]; then
      echo "Warning: Backup is available for restore, but it's being skipped because it's already initialized or the data directory is not empty."
    else
      # Check if manticore-backup is installed
      if ! command -v manticore-backup > /dev/null; then
        echo -e "${RED}manticore-backup isn't installed${NC}"
        exit 1
      fi

      find ${BACKUP_INIT_FOLDER}/config -type f -exec sh -c 'rm -f "${1#/docker-entrypoint-initdb.d/config}"' sh {} \;
      find ${BACKUP_INIT_FOLDER}/state -type f -exec sh -c 'rm -f "${1#/docker-entrypoint-initdb.d/state}"' sh {} \;

      manticore-backup --version
      manticore-backup --force --backup-dir='/' --restore='docker-entrypoint-initdb.d'
    fi
  fi

  exec "$@"
}

# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
  _main "$@"
fi
