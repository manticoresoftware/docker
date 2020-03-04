# Manticore Search Docker image

This is the git repo of official [Docker image](https://hub.docker.com/r/manticoresearch/manticore/) for [Manticore Search](https://manticoresearch.com/).

Manticore Search is a powerful free open source search engine with a focus on low latency and high throughput full-text search and high volume stream filtering. It helps thousands of companies from small to large, such as Craigslist, to search and filter petabytes of text data on a single or hundreds of nodes, do stream full-text filtering, add auto-complete, spell correction, more-like-this, faceting and other search-related technologies to their sites.

The default configuration includes a sample Real-Time index and listens on the default ports:
  * `9306` for connections from a MySQL client
  * `9308` for connections via HTTP
  * `9312` for connections via a binary protocol (e.g. in case you run a cluster)

The image comes with libraries for easy indexing data from MySQL, PostgreSQL XML and CSV files.

# How to run this image

## Quick usage

The below is the simplest way to start Manticore in a container and log in to it via mysql client:
  
```
docker run --name manticore --rm -d manticoresearch/manticore \
&& docker exec -it manticore mysql -w \
&& docker stop manticore
```

When you exit from the mysql client it stops and removes the container, so use it only for testing / sandboxing purposes. See below how to use it in production.

The image comes with a sample index which can be loaded like this:

```
mysql> source sandbox.sql
```

Also the mysql client has in history several sample queries that you can run on the above index, just use Up/Down arrows in the client to see and run them.

## Production use 


### Mounting points

The image comes with a volume at `/var/lib/manticore/`, which can be mounted to local folder for persistence.
To use a custom configuration file, mount `/etc/manticoresearch/manticore.conf`. 
The ports are 9306/9308/9312 for SQL/HTTP/Binary, expose them depending on how you are going to use Manticore. For example:

```
docker run --name manticore -v ~/manticore/etc/manticore.conf:/etc/manticoresearch/manticore.conf -v ~/manticore/data/:/var/lib/manticore -p 9306:9306 -p 9308:9308 -d manticoresearch/manticore
```

### Docker-compose

In many cases you might want to use Manticore together with other images specified in a docker-compose YAML file. Here is the minimal recommend specification for Manticore Search in docker-compose.yml:

```
version: '2.2'

services:
  manticore:
    container_name: manticore
    image: manticoresearch/manticore
    restart: always
    ulimits:
      nproc: 65535
      nofile:
         soft: 65535
         hard: 65535
      memlock:
        soft: -1
        hard: -1
    volumes:
      - ~/data:/var/lib/manticore
#      - manticore.conf:/etc/manticoresearch/manticore.conf # uncommment if you use a custom config
```

You can connect to it by running `docker-compose exec manticore mysql`.

### HTTP protocol

HTTP protocol is exposed on port 9308. You can map the port locally and connect with curl:

```
docker run --name manticore -p 9308:9308 -d manticoresearch/manticore
```

Create a table:
```
curl -X POST 'http://127.0.0.1:9308/sql' -d 'mode=raw&query=CREATE TABLE testrt ( title text, content text, gid integer)'
```
Insert a document:

```
curl -X POST 'http://127.0.0.1:9308/json/insert' -d'{"index":"testrt","id":1,"doc":{"title":"Hello","content":"world","gid":1}}'
```

Perform a simple search:

```
curl -X POST 'http://127.0.0.1:9308/json/search' -d '{"index":"testrt","query":{"match":{"*":"hello world"}}}'
```

### Logging

By default, the daemon is set to send it's logging to `/dev/stdout`, which can be viewed from the host with:


```
docker logs manticore
```

The query log can be diverted to Docker log by passing variable `QUERY_LOG_TO_STDOUT=true`.



### Multi-node cluster with replication

A simple `stack.yml` for defining a two node cluster:

```
version: '2.2'

services:

  manticore-1:
    image: manticoresearch/manticore
    restart: always
    ulimits:
      nproc: 65535
      nofile:
         soft: 65535
         hard: 65535
      memlock:
        soft: -1
        hard: -1
    networks:
      - manticore
  manticore-2:
    image: manticoresearch/manticore
    restart: always
    ulimits:
      nproc: 65535
      nofile:
        soft: 65535
        hard: 65535
      memlock:
        soft: -1
        hard: -1
    networks:
      - manticore
networks:
  manticore:
    driver: bridge
```
We start it with `docker-compose -f stack.yml up` .
Next, we need to create the cluster: we enter on the first instance and defined the cluster and attach the sample index to it:

```
$ docker exec -it docker_manticore-1_1 mysql

mysql> CREATE TABLE testrt ( title text, content text, gid integer);

mysql> CREATE CLUSTER posts;
Query OK, 0 rows affected (0.24 sec)

mysql> ALTER CLUSTER posts ADD testrt;
Query OK, 0 rows affected (0.07 sec)

```

And on second instance we join it to the cluster:

```
$ docker exec -it docker_manticore-2_1 mysql

mysql> JOIN CLUSTER posts AT 'docker_manticore-1_1:9312';
mysql> INSERT INTO posts:testrt(title,content,gid)  VALUES('hello','world',1);
Query OK, 1 row affected (0.00 sec)
```

If we go back to the first instance we'll see the new record:
```
$ docker exec -it docker_manticore-1_1 mysql

mysql> select * from testrt;
+---------------------+------+-------------+-----------------------------------------------------------------------------------------------------------------------------+
| id                  | gid  | title       | content                                                                                                                     |
+---------------------+------+-------------+-----------------------------------------------------------------------------------------------------------------------------+
|                   1 |    1 | Hello World | Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. |
| 3891545739431510017 |    1 | hello       | world                                                                                                                       |
+---------------------+------+-------------+-----------------------------------------------------------------------------------------------------------------------------+
2 rows in set (0.00 sec)

```

## Memory locking and limits

It's recommended to overwrite the default ulimits of docker for the Manticore instance:

```
 --ulimit nofile=65536:65536
```


For best performance, index components can be mlocked into memory. When Manticore is run under Docker, the instance requires additional privileges to allow memory locking. The following options must be added when running the instance:

```
  --cap-add=IPC_LOCK --ulimit memlock=-1:-1 
```


## Custom config

If you want to run Manticore with your custom config, where indexes are defined in the configuration mode - you will need to mount the configuration to the instance:

```
docker run --name manticore -v ~/manticore/etc/manticore.conf:/etc/manticoresearch/manticore.conf -v ~/manticore/data/:/var/lib/manticore/data -p 9306:9306 -d manticoresearch/manticore
```

`searchd` daemon runs under `manticore`, performing operations on index files (like creating or rotation plain indexes) should be made under `manticore` user (otherwise files will be created under `root` and `searchd` can't manipulate them):

```
docker exec -it manticore gosu manticore indexer --all --rotate
```
 
# Issues

For reporting issues, please use the [issue tracker](https://github.com/manticoresoftware/docker/issues).

