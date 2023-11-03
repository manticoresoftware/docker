# Manticore Search Docker image

This is the git repo of official [Docker image](https://hub.docker.com/r/manticoresearch/manticore/) for [Manticore Search](https://github.com/manticoresoftware/manticoresearch).

❗ Please note: This is a development version repo. For the latest release's information, refer to the readme at https://github.com/manticoresoftware/docker/tree/docker-6.2.12

Manticore Search is an easy to use open source fast database for search. It helps thousands of companies from small to large, such as Craigslist, to search and filter petabytes of text data on a single or hundreds of nodes, do stream full-text filtering, add auto-complete, spell correction, more-like-this, faceting and other search-related technologies to their websites and applications.

The default configuration includes a sample Real-Time index and listens on the default ports:
  * `9306` for connections from a MySQL client
  * `9308` for connections via HTTP
  * `9312` for connections via a binary protocol (e.g. in case you run a cluster)

The image comes with libraries for easy indexing data from MySQL, PostgreSQL XML and CSV files.

# How to run Manticore Search Docker image

## Quick usage

The below is the simplest way to start Manticore in a container and log in to it via the mysql client:

```bash
docker run -e EXTRA=1 --name manticore --rm -d manticoresearch/manticore && echo "Waiting for Manticore docker to start. Consider mapping the data_dir to make it start faster next time" && until docker logs manticore 2>&1 | grep -q "accepting connections"; do sleep 1; echo -n .; done && echo && docker exec -it manticore mysql && docker stop manticore
```

Note that upon exiting the MySQL client, the Manticore container will be stopped and removed, resulting in no saved data. For information on using Manticore in a production environment, please see below.

The image comes with a sample table that can be loaded like this:

```sql
mysql> source /sandbox.sql
```

Also, the mysql client has several sample queries in its history that you can run on the above table, just use Up/Down keys in the client to see and run them.

## Production use


### Ports and mounting points

For data persistence the folder `/var/lib/manticore/` should be mounted to local storage or other desired storage engine.

The configuration file inside the instance is located at   `/etc/manticoresearch/manticore.conf`. For custom settings, this file should be mounted to your own configuration file.

The ports are 9306/9308/9312 for SQL/HTTP/Binary, expose them depending on how you are going to use Manticore. For example:

```bash
docker run -e EXTRA=1 --name manticore -v $(pwd)/data:/var/lib/manticore -p 127.0.0.1:9306:9306 -p 127.0.0.1:9308:9308 -d manticoresearch/manticore
```

or

```bash
docker run -e EXTRA=1 --name manticore -v $(pwd)/manticore.conf:/etc/manticoresearch/manticore.conf -v $(pwd)/data:/var/lib/manticore/ -p 127.0.0.1:9306:9306 -p 127.0.0.1:9308:9308 -d manticoresearch/manticore
```

Make sure to remove `127.0.0.1:` if you want the ports to be available for external hosts.

### Manticore Columnar Library and Manticore Buddy

The Manticore Search Docker image doesn't come with the [Manticore Columnar Library](https://github.com/manticoresoftware/columnar) pre-installed, which is necessary if you require columnar storage and secondary indexes. However, it can easily be enabled during runtime by setting the environment variable `EXTRA=1`. For example, `docker run -e EXTRA=1 ... manticoresearch/manticore`. This will download and install the library in the data directory (which is typically mapped as a volume in production environments) and it won't be re-downloaded unless the Manticore Search version is changed.

Using `EXTRA=1` also activates [Manticore Buddy](https://github.com/manticoresoftware/manticoresearch-buddy), which is used for processing certain commands. For more information, refer to the [changelog](https://manual.manticoresearch.com/Changelog#Version-6.0.0).

If you only need the MCL, you can use the environment variable `MCL=1`.

### Docker-compose

In many cases, you may want to use Manticore in conjunction with other images specified in a Docker Compose YAML file. Below is the minimal recommended configuration for Manticore Search in a docker-compose.yml file:

```yaml
version: '2.2'

services:
  manticore:
    container_name: manticore
    image: manticoresearch/manticore
    environment:
      - EXTRA=1
    restart: always
    ports:
      - 127.0.0.1:9306:9306
      - 127.0.0.1:9308:9308
    ulimits:
      nproc: 65535
      nofile:
         soft: 65535
         hard: 65535
      memlock:
        soft: -1
        hard: -1
    volumes:
      - ./data:/var/lib/manticore
#      - ./manticore.conf:/etc/manticoresearch/manticore.conf # uncomment if you use a custom config
```

Besides using the exposed ports 9306 and 9308, you can log into the instance by running `docker-compose exec manticore mysql`.

### HTTP protocol

HTTP protocol is exposed on port 9308. You can map the port locally and connect using curl.:

```bash
docker run -e EXTRA=1 --name manticore -p 9308:9308 -d manticoresearch/manticore
```

<!-- example create -->
Create a table:

<!-- request JSON -->
```bash
curl -X POST 'http://127.0.0.1:9308/sql' -d 'mode=raw&query=CREATE TABLE testrt ( title text, content text, gid integer)'
```
<!-- end -->
<!-- example insert -->
Insert a document:

<!-- request JSON -->
```bash
curl -X POST 'http://127.0.0.1:9308/json/insert' -d'{"index":"testrt","id":1,"doc":{"title":"Hello","content":"world","gid":1}}'
```
<!-- end -->
<!-- example search -->
Perform a simple search:

<!-- request JSON -->
```bash
curl -X POST 'http://127.0.0.1:9308/json/search' -d '{"index":"testrt","query":{"match":{"*":"hello world"}}}'
```
<!-- end -->

### Logging

By default, the server is set to send its logging to `/dev/stdout`, which can be viewed from the host with:


```bash
docker logs manticore
```

The query log can be diverted to Docker log by passing the variable `QUERY_LOG_TO_STDOUT=true`.


### Multi-node cluster with replication

Here is a simple `docker-compose.yml` for defining a two node cluster:

```yaml
version: '2.2'

services:

  manticore-1:
    image: manticoresearch/manticore
    environment:
      - EXTRA=1
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
    environment:
      - EXTRA=1
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
* Start it: `docker-compose up`
* Create a cluster:
  ```sql
  $ docker-compose exec manticore-1 mysql

  mysql> CREATE TABLE testrt ( title text, content text, gid integer);

  mysql> CREATE CLUSTER posts;
  Query OK, 0 rows affected (0.24 sec)

  mysql> ALTER CLUSTER posts ADD testrt;
  Query OK, 0 rows affected (0.07 sec)

  MySQL [(none)]> exit
  Bye
  ```
* Join to the the cluster on the 2nd instance
  ```sql
  $ docker-compose exec manticore-2 mysql

  mysql> JOIN CLUSTER posts AT 'manticore-1:9312';
  mysql> INSERT INTO posts:testrt(title,content,gid)  VALUES('hello','world',1);
  Query OK, 1 row affected (0.00 sec)

  MySQL [(none)]> exit
  Bye
  ```
* If you now go back to the first instance you'll see the new record:
  ```sql
  $ docker-compose exec manticore-1 mysql

  MySQL [(none)]> select * from testrt;
  +---------------------+------+-------+---------+
  | id                  | gid  | title | content |
  +---------------------+------+-------+---------+
  | 3891565839006040065 |    1 | hello | world   |
  +---------------------+------+-------+---------+
  1 row in set (0.00 sec)

  MySQL [(none)]> exit
  Bye
  ```

## Memory locking and limits

It's recommended to overwrite the default ulimits of docker for the Manticore instance:

```bash
 --ulimit nofile=65536:65536
```

For best performance, table components can be "mlocked" into memory. When Manticore is run under Docker, the instance requires additional privileges to allow memory locking. The following options must be added when running the instance:

```bash
  --cap-add=IPC_LOCK --ulimit memlock=-1:-1
```

## Configuring Manticore Search with Docker

If you want to run Manticore with a custom configuration that includes table definitions, you will need to mount the configuration to the instance:

```bash
docker run -e EXTRA=1 --name manticore -v $(pwd)/manticore.conf:/etc/manticoresearch/manticore.conf -v $(pwd)/data/:/var/lib/manticore -p 127.0.0.1:9306:9306 -d manticoresearch/manticore
```

Take into account that Manticore search inside the container is run under user `manticore`. Performing operations with table files (like creating or rotating plain tables) should be also done under `manticore`. Otherwise the files will be created under `root` and the search daemon won't have rights to open them. For example here is how you can rotate all tables:

```bash
docker exec -it manticore gosu manticore indexer --all --rotate
```

You can also set individual `searchd` and `common` configuration settings using Docker environment variables.  

The settings must be prefixed with their section name, example for in case of `mysql_version_string` the variable must be named `searchd_mysql_version_string`:


```bash
docker run -e EXTRA=1 --name manticore  -p 127.0.0.1:9306:9306  -e searchd_mysql_version_string='5.5.0' -d manticoresearch/manticore
```

In case of the `listen` directive, new listening interfaces using the Docker variable `searchd_listen`  in addition to the default ones. Multiple interfaces can be declared, separated by a semi-colon ("|"). To listen only on a network address, the `$ip` (retrieved internally from `hostname -i`) can be used as address alias.

For example `-e searchd_listen='9316:http|9307:mysql|$ip:5443:mysql_vip'` will add an additional SQL interface on port 9307, an SQL VIP listener on port 5443 running only on the instance's IP, and an HTTP listener on port 9316, in addition to the defaults on 9306 and 9308, respectively.

```bash
$ docker run -e EXTRA=1 --rm -p 1188:9307  -e searchd_mysql_version_string='5.5.0' -e searchd_listen='9316:http|9307:mysql|$ip:5443:mysql_vip'  manticore
[Mon Aug 17 07:31:58.719 2020] [1] using config file '/etc/manticoresearch/manticore.conf' (9130 chars)...
listening on all interfaces for http, port=9316
listening on all interfaces for mysql, port=9307
listening on 172.17.0.17:5443 for VIP mysql
listening on all interfaces for mysql, port=9306
listening on UNIX socket /var/run/mysqld/mysqld.sock
listening on 172.17.0.17:9312 for sphinx
listening on all interfaces for http, port=9308
prereading 0 indexes
prereaded 0 indexes in 0.000 sec
accepting connections
```

### Startup flags

To start Manticore with custom startup flags, specify them as arguments when using docker run. Ensure you do not include the `searchd` command and include the `--nodetach` flag. Here's an example:
```bash
docker run -e EXTRA=1 --name manticore --rm manticoresearch/manticore:latest --replay-flags=ignore-trx-errors --nodetach
```

### Running under non-root
By default, the main Manticore process `searchd` is running under user `manticore` inside the container, but the script which runs on starting the container is run under your default docker user which in most cases is `root`. If that's not what you want you can use `docker ... --user manticore` or `user: manticore` in docker compose yaml to make everything run under `manticore`. Read below about possible volume permissions issue you can get and how to solve it.


### Building plain tables on startup

There are several methods to build plain tables from your custom configuration file. Each method utilizes the environment variable `CREATE_PLAIN_TABLES` (`docker run -e CREATE_PLAIN_TABLES=...`)

1) **Build all plain tables on startup:**  
   Simply set the environment variable to `CREATE_PLAIN_TABLES=1`.

2) **Build specific tables on startup:**  
   To initiate indexing for specific tables, use the following syntax: `CREATE_PLAIN_TABLES=tbl1;tbl2`.

3) **Scheduled cron-based building of specific tables:**  
   Schedule indexing tasks for specific tables using the format `CREATE_PLAIN_TABLES={table name}:{crontab schedule command}`.
    * For a single table, use: `CREATE_PLAIN_TABLES=tbl:* * * * *`.
    * To index multiple tables, format it like this: `CREATE_PLAIN_TABLES=tbl:* * * * *;tbl2:*/5 2 * * *`.

4) **Combining cron-based and startup table rebuilding:**  
   To combine cron-based indexing with the indexing of desired tables on startup, use this format: `CREATE_PLAIN_TABLES=tbl:* * * * *;tbl2:*/5 2 * * *;deltaTable;tbl3`.

# Backup and restore

### Full backup

To create a **full backup**, you need to include the `-e EXTRA=1` flag. 
The `manticore-backup` package utilizes the `manticore-executor`, which is installed with the EXTRA packages.

Creating a **full backup** is a straightforward process. Simply run the following command:

```bash
docker exec -it CONTAINER-ID manticore-backup --backup-dir=/tmp
```
This command will generate a backup in your `/tmp/` directory.

```bash
$ ls /tmp/ | grep backup-*
backup-20230509133521
```
Inside this folder, you will find your backup.

### Restore full dump


To restore your full backup, you need to mount your backup to the `/docker-entrypoint-initdb.d` folder. 
Please note that you should mount the content of your backup, not the backup folder itself (e.g., `backup-202307..`).

The restore process temporarily prevents the regular `searchd` start. 
If you wish to avoid this behavior, you can set the flag `-e START_AFTER_RESTORE=true`.

### Creating SQL dumps

The simplest way to ensure this is to use `docker exec` and run the tool from the same container. Here's an example:

```bash
docker exec some-mysql sh -c 'exec mysqldump' > /some/path/on/your/host/dump.sql
```

### Restore SQL dumps

For restoring data, you can use the `docker exec` command with the `-i` flag, similar to the following:

```bash
docker exec -i MANTICORE_CONTAINER sh -c 'exec mysql' < /some/path/on/your/host/dump.sql
```

# Building docker image with buildx

To build multi-arch images, we use the buildx docker plugin. Before building, follow these steps:

```bash
docker buildx create  --name manticore_build --platform linux/amd64,linux/arm64
docker buildx use manticore_build
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

Once the above steps are completed, run the following `build` and `push` commands:

```bash
docker buildx build --push --build-arg DEV=1 --platform linux/arm64,linux/amd64 --tag  manticoresearch/manticore:$BUILD_TAG .
```

# Troubleshooting

### Permissions issue with a mounted volume

In case you are running Manticore Search docker under non-root (using `docker ... --user manticore` or `user: manticore` in docker compose yaml), you can face a permissions issue, for example:
```bash
FATAL: directory /var/lib/manticore write error: failed to open /var/lib/manticore/tmp: Permission denied
```

or in case you are using `-e EXTRA=1`:

```bash
mkdir: cannot create directory ‘/var/lib/manticore/.mcl/’: Permission denied
```

This can happen because the user which is used to run processes inside the container may have no permissions to modify the directory you have mounted to the container. To fix it you can `chown` or `chmod` the mounted directory. If you run the container under user `manticore` you need to do:
```bash
chown -R 999:999 data
```

since user `manticore` has ID 999 inside the container.

# Issues

For reporting issues, please use the [issue tracker](https://github.com/manticoresoftware/docker/issues).
