# Manticore Search Docker image

This is the official repository of the [Docker image](https://hub.docker.com/r/manticoresearch/manticore/) for [Manticore Search](https://github.com/manticoresoftware/manticore).

Manticore Search is an open source full-text search server. The image use currently Debian Stretch as the operating system.

The searchd daemon runs in nodetach mode. Default configuration includes includes a simple Real-Time index and listen on the default ports ( `9306`  for SphinxQL and `9312` for SphinxAPI).

The image comes with MySQL  and PostgreSQL client libraries for indexing data from these databases as well as expat library for indexing data from XML files.


# How to run this image

## Quick usage

  ```
	docker run --name manticore -p 9306:9306 -d manticoresearch/manticore
  ```
  
  In another console:
  
  ```
  $ mysql -h0 -P9306
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 1
Server version: 2.6.1 e049fec@180113 release 

Copyright (c) 2000, 2017, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql> SHOW TABLES;
+--------+------+
| Index  | Type |
+--------+------+
| testrt | rt   |
+--------+------+
1 row in set (0,00 sec)

mysql> INSERT INTO testrt(id,title,content,gid) VALUES(1,'Hello','World',10);
Query OK, 1 row affected (0.00 sec)

mysql> SELECT * FROM testrt;
+------+------+
| id   | gid  |
+------+------+
|    1 |   10 |
+------+------+
1 row in set (0,00 sec)
```

To shutdown the daemon:

```
  docker stop manticore
```

## Mounting points

The configuration folder inside the image is the usual `/etc/manticoresearch`. 
Index files are located at `/var/lib/manticore/data` and logs at `/var/log/manticore`.
For persistence, mount these points to your local folders.

```
docker run --name manticore -v ~/manticore/etc/:/etc/manticoresearch/ -v ~/manticore/data/:/var/lib/manticore/data -v ~/manticore/logs/:/var/log/manticore -p 9306:9306 -d manticoresearch/manticore
```
    
In `~/manticore/` you need to create the `etc/`,`data/` and `logs/` folders, as well as add a valid  [manticore.conf](https://github.com/manticoresoftware/docker/blob/master/manticore.conf)   in `~/manticore/etc/`.  

`searchd` daemon runs under `manticore`, performing operations on index files (like creating or rotation plain indexes) should be made under `manticore` user (otherwise files will be created under `root` and `searchd` can't manipulate them).

## Rotating indexes

```
docker exec -it manticore gosu manticore indexer --all --rotate
```

## Default configuration

```
index testrt {
    type = rt
    rt_mem_limit = 128M
    path = /var/lib/manticore/data/testrt
    rt_field = title
    rt_field = content
    rt_attr_uint = gid
}
index pq {
    type = percolate
    path = /var/lib/manticore/data/pq
    min_infix_len   = 4
}
searchd {
    listen = 9306:mysql41
    listen = <your ip>:9312
    listen = 9308:http
    
    listen = $ip:9315-9325:replication
    log = /var/log/manticore/searchd.log
    query_log = /var/log/manticore/query.log
    read_timeout = 5
    max_children = 30
    pid_file = /var/run/manticore/searchd.pid
    seamless_rotate = 1
    preopen_indexes = 1
    unlink_old = 1
    workers = thread_pool
    binlog_path = /var/lib/manticore/data
    max_packet_size = 128M
    mysql_version_string = 5.5.21
    data_dir = /var/lib/manticore/replication
}
```

## Logging

searchd runs with ``--no-detach`` option, sending it's log to `/dev/stdout`, which can be seen with 

```
  docker logs manticore
```

You can also send the query logs to `/dev/stdout` to be viewed using `docker logs`.
Alternative, you can monitor the query log directly by doing 

```
  docker exec -it manticore tail -f /var/lib/manticore/log/query.log
```

## Replication

To create a PQ replication cluster we need to create a docker network first.

```
docker network create manticorepl
```
Next we launch 2 docker instaces with SphinxQL port exposed:

```
docker run --name manti1--network=manticorepl -p 11906:9306 manticoresearch/manticore
```

```
docker run --name manti2 --network=manticorepl -p 11907:9306 manticoresearch/manticore
```
On first instance we login, create the cluster and add the sample `pq` percolate index to it:

```
mysql -P11906 -h0

mysql> CREATE CLUSTER posts;
mysql> ALTER CLUSTER posts ADD pq;
```

And on second instance we join it to the cluster:

```
mysql -P11907 -h0

mysql> JOIN CLUSTER posts AT 'manti1:9312';
```

At this point we can start adding queries in any instance and they will be replicated across the cluster.

# Memory locking and limits

For best performance, index components can be mlocked into memory. When Manticore is run under Docker, the instance requires additional privileges to allow memory locking. The following options must be added when running the instance:

```
  --cap-add=IPC_LOCK --ulimit memlock=-1:-1 
```
In addition, if the search instance loads a lot of indexes or has a high number of connections, the default file descriptor limits may be reached.  In these case the limit for file descriptors must be set:

```
--ulimit nofile=65536:65536
```

# Issues

For reporting issues, please use the [issue tracker](https://github.com/manticoresoftware/docker/issues).

