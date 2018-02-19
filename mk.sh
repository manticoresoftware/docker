#!/bin/bash
mkdir -p /var/lib/manticore/data/
mkdir -p /var/lib/manticore/log/
cd /build/manticore/build/src
./searchd
echo "insert into rt (id,title,content,gid) values (1,'Hello','world',10);" | mysql -h0 -P9306
./searchd --stopwait

