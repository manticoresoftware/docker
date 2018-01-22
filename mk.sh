#!/bin/bash
echo "hello"
cd /build/manticore/build/src
mkdir -p /var/lib/manticore/data/
mkdir -p /var/lib/manticore/log/
cat << DEMO_CONFIG >sphinx.conf
index demo {
    type = rt
    rt_mem_limit = 128M
    path = /var/lib/manticore/data/demo
    rt_field = title
    rt_field = content
    rt_attr_string = title
    rt_attr_string = content
    rt_attr_uint = gid
}
searchd {
    listen = 9312
    listen = 9306:mysql41
    log = /var/lib/manticore/log/searchd.log
    query_log = /var/lib/manticore/log/query.log
    read_timeout = 5
    max_children = 30
    pid_file = /var/run/searchd.pid
    seamless_rotate = 1
    preopen_indexes = 1
    unlink_old = 1
    workers = threads # for RT to work
    binlog_path = /var/lib/manticore/data
}

DEMO_CONFIG
./searchd
echo "insert into demo (id,title,content,gid) values (1,'Hello','world',10);" | mysql -h0 -P9306
./searchd --stopwait

