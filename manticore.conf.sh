#!/bin/bash

if [[ $(grep -e "#!\/bin\/sh" -e "#!\/bin\/bash" /etc/manticoresearch/manticore.conf) ]]; then
  executableConfig=1
fi

if [ -z $executableConfig ]; then
  conf=$(cat /etc/manticoresearch/manticore.conf)
else
  conf=$(bash /etc/manticoresearch/manticore.conf)
fi

if [ -z "$searchd_listen" ]; then
  confHash=$(md5sum /etc/manticoresearch/manticore.conf | awk '{print $1}')
  expectedConfHash=$(cat /manticore.conf.md5)

  if [[ "$confHash" == "$expectedConfHash" ]]; then
    export searchd_listen='9306:mysql41|/var/run/mysqld/mysqld.sock:mysql41|9308:http|$ip:9312|$ip:9315-9325:replication'
  fi
fi

while IFS='=' read -r envVariable value; do
  if [[ "${envVariable}" == searchd_* ]]; then
    hasSearchdEnv=1
  elif [[ "${envVariable}" == common_* ]]; then
    hasCommonEnv=1
  fi
done < <(env)



if [[ -n $hasCommonEnv && ! $(echo $conf | grep -E "common\s*{") ]]; then
    conf="$(echo "${conf}")
common {
}"
fi


if [[ -n $hasSearchdEnv && ! $(echo $conf | grep -E "searchd\s*{") ]]; then
    conf="$(echo "${conf}")
searchd {
}"
fi

if hostname -i > /dev/null 2>&1; then
  hostip=$(hostname -i|rev|cut -d\  -f 1|rev)
elif hostname -I > /dev/null 2>&1; then
  hostip=$(hostname -I|cut -d\  -f 1)
else
  hostip="0.0.0.0"
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
      conf=$(echo "${conf}" | sed -e "s/^\s*listen\s*=.*$//g" | sed -r '/^\s*$/d')
      IFS='|' read -ra LISTEN_VALUES <<<"$value"
      count=0

      for i in "${LISTEN_VALUES[@]}"; do
        i=${i/\$ip/$hostip}
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


echo "${conf}" > /etc/manticoresearch/manticore.conf.debug
echo "${conf}"
