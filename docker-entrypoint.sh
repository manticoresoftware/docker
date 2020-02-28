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
    sed -i 's/\/var\/log\/manticore\/query.log/\/dev\/stdout' /etc/manticoresearch/manticore.conf
  fi

}
_main() {
  # first arg is `h` or some `--option`
  if [ "${1#-}" != "$1" ]; then
    set -- searchd  "$@"
  fi
  if [ "$1" = 'searchd' ] && ! _searchd_want_help "@"; then
    docker_setup_env "$@"
    # allow the container to be started with `--user`
    if [ "$(id -u)" = '0' ]; then
      find /var/lib/manticore /var/log/manticore /var/run/manticore /etc/manticoresearch \! -user manticore -exec chown manticore '{}' +
      exec gosu manticore "$0" "$@"
    fi
  fi
  exec "$@"
}
# If we are sourced from elsewhere, don't perform any further actions
if ! _is_sourced; then
  _main "$@"
fi

