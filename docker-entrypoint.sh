#!/bin/sh
set -e

# first arg is `h` or some `--option`
if [ "${1#-}" != "$1" ]; then
	set -- searchd "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'searchd'  -a "$(id -u)" = '0' ]; then
	find /var/lib/manticore /var/log/manticore /var/run/manticore /etc/manticoresearch  \! -user manticore -exec chown manticore '{}' +
	exec gosu manticore "$0" "$@"
fi

exec "$@"
