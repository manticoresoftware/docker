#!/bin/bash

SED_QUERY=""

while IFS='=' read -r oldname value; do
  if [[ $oldname == 'searchd_'* || $oldname == 'common_'* ]]; then
    value=$(echo ${!oldname} | sed 's/\//\\\//g')
    oldname=$(echo $oldname | sed "s/searchd_//g;s/common_//g;")
    newname=$oldname

    if [[ $newname == 'listen_env' ]]; then
      newname="listen"
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

    echo "Replace in confg $newname = $value"

    if [[ -z $SED_QUERY ]]; then
      SED_QUERY="s/(#\s)*?$oldname\s?=\s?.*?$/$newname = $value/g"
    else
      SED_QUERY="$SED_QUERY;s/(#\s)*?$oldname\s?=\s?.*?$/$newname = $value/g"
    fi

  fi
done < <(env)

if [[ ! -z $SED_QUERY ]]; then
  sed -i -E "$SED_QUERY" /etc/manticoresearch/manticore.conf
fi

exec searchd --nodetach