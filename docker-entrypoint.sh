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
      echo -e "${GREEN}Install extra packages${NC}"

      install_extra $EXTRA_URL $EXTRA_INSTALLED_VERSION_PATH $NEW_EXTRA_VERSION $EXTRA_DIR
    else
      INSTALLED_EXTRA_VERSION=$(cat $EXTRA_INSTALLED_VERSION_PATH)

      if [[ $INSTALLED_EXTRA_VERSION != $NEW_EXTRA_VERSION ]]; then
        echo -e "${RED}Extra packages version mismatch. Updating...${NC}"
        install_extra $EXTRA_URL $EXTRA_INSTALLED_VERSION_PATH $NEW_EXTRA_VERSION $EXTRA_DIR 1
      fi
    fi

    MCL="1"

  else
    if [[ $(du /usr/bin/manticore-executor | awk '{print $1}') -eq 0 ]]; then
      export searchd_buddy_path=
    fi

  fi

  if [[ "${MCL}" == "1" ]]; then
    MCL_DIR="/var/lib/manticore/.mcl/"
    LIB_MANTICORE_COLUMNAR="${MCL_DIR}lib_manticore_columnar.so"
    LIB_MANTICORE_SECONDARY="${MCL_DIR}lib_manticore_secondary.so"
    LIB_MANTICORE_KNN="${MCL_DIR}lib_manticore_knn.so"
    LIB_MANTICORE_GALERA="${MCL_DIR}libgalera_manticore.so"
    GALERA_VERSION=$(cat /mcl_galera.url | cut -d" " -f1 | cut -d"-" -f3 | cut -d"_" -f2)
    COLUMNAR_VERSION=$(cat /mcl_galera.url | cut -d" " -f2 | cut -d"-" -f6 | cut -d"_" -f1)

    [ -L /usr/share/manticore/modules/lib_manticore_columnar.so ] || ln -s $LIB_MANTICORE_COLUMNAR /usr/share/manticore/modules/lib_manticore_columnar.so
    [ -L /usr/share/manticore/modules/lib_manticore_secondary.so ] || ln -s $LIB_MANTICORE_SECONDARY /usr/share/manticore/modules/lib_manticore_secondary.so
    [ -L /usr/share/manticore/modules/lib_manticore_knn.so ] || ln -s $LIB_MANTICORE_KNN /usr/share/manticore/modules/lib_manticore_knn.so
    [ -L /usr/share/manticore/modules/libgalera_manticore.so ] || ln -s $LIB_MANTICORE_GALERA /usr/share/manticore/modules/libgalera_manticore.so

    searchd -v | grep -i error | egrep "trying to load" &&
      rm $LIB_MANTICORE_COLUMNAR $LIB_MANTICORE_SECONDARY $LIB_MANTICORE_KNN $LIB_MANTICORE_GALERA &&
      echo "WARNING: wrong MCL version has been removed, installing the correct one"

    if ! searchd --version | head -n 1 | grep $COLUMNAR_VERSION; then
      echo "Columnar version mismatch"
      rm $LIB_MANTICORE_COLUMNAR > /dev/null 2>&1  || echo "Columnar lib is not installed"
      rm $LIB_MANTICORE_SECONDARY > /dev/null 2>&1  || echo "Secondary lib is not installed"
      rm $LIB_MANTICORE_KNN > /dev/null 2>&1  || echo "KNN lib is not installed"
    fi

    if [[ -f /usr/share/manticore/modules/libgalera_manticore.so && \
    ! $(strings /usr/share/manticore/modules/libgalera_manticore.so | grep -E '^[0-9]+\.[0-9]+\([a-z0-9]+\)' | grep $GALERA_VERSION) ]]; then
          echo "Galera version mismatch"
          rm $$LIB_MANTICORE_GALERA > /dev/null 2>&1 || echo "Galera lib is not installed"
    fi


    if [[ ! -f "$LIB_MANTICORE_COLUMNAR" || ! -f "$LIB_MANTICORE_SECONDARY" || ! -f "$LIB_MANTICORE_KNN" || ! -f "$LIB_MANTICORE_GALERA"  ]]; then
      if ! mkdir -p ${MCL_DIR}; then
        echo "ERROR: Manticore Columnar Library is inaccessible: couldn't create ${MCL_DIR}."
        exit
      fi

      MCL_URL=$(cat /mcl_galera.url)
      wget --show-progress -q -P /tmp $MCL_URL

      LAST_PATH=$(pwd)

      for package in columnar galera; do
        cd /tmp

        PACKAGE_NAME=$(ls | grep "manticore-${package}" | head -n 1)

        mkdir ${package} && mv "$PACKAGE_NAME" ${package} && cd ${package}
        ar -x $PACKAGE_NAME
        tar -xf data.tar.gz
        if [ ${package} = "galera" ]; then
          mv usr/share/doc/manticore-galera/* /usr/share/doc/manticore-galera
        fi
        find . -name '*.so' -exec cp {} ${MCL_DIR} \;
      done;

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
    wget --show-progress -q -P $4 $1
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

  BACKUP_INIT_FOLDER="/docker-entrypoint-initdb.d"

  if [ -f "${BACKUP_INIT_FOLDER}/versions.json" ]; then
    if [ -f /var/lib/manticore/manticore.json ]; then
      echo "Warning: Backup is available for restore, but it's being skipped because it's already initialized or the data directory is not empty."
    else
      if [ ! -s "/usr/bin/manticore-executor" ]; then
          echo -e "${RED}Can't run manticore-backup. Use env. var. EXTRA=1 to install the missing packages.${NC}"
          exit 1
      fi

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
