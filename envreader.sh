#!/bin/bash

conf=$(cat /etc/manticoresearch/manticore.conf)

if [[ ! $(echo $conf | grep -E "common\s*{") ]]; then
    conf="$(echo "${conf}")
common {
}"
fi

if [[ ! $(echo $conf | grep -E "searchd\s*{") ]]; then
    conf="$(echo "${conf}")
searchd {
}"
fi


while IFS='=' read -r envVariable value; do

  if [[ "${envVariable}" == searchd_* || "${envVariable}" == common_* ]]; then

    if [[ "${envVariable}" == searchd_* ]]; then
        section="searchd"
      else
        section="common"
    fi

    value=$(echo ${!envVariable} | sed 's/\//\\\//g')
    cleaned_key=$(echo $envVariable | sed "s/${section}_//")

          if [[ $cleaned_key == 'listen' ]]; then

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

    pattern="\s*${cleaned_key}\s*="
    if [[ ${conf} =~ $pattern ]]; then
      conf=$(echo "${conf}" | sed -e "s/^\s*${cleaned_key}\s*=.*$/    ${cleaned_key} = ${value}/g")
    else
      conf=$(echo "${conf}" | sed -e "/^\s*${section}\s*{/a \    ${cleaned_key} = ${value}")
    fi

  fi

done < <(env)


echo "${conf}"
