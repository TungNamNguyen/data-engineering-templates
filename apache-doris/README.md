# Apache Doris

Apache Doris is a high-performance, real-time analytical database. It uses a MySQL-compatible protocol, so you can connect with any MySQL client, JDBC driver, or BI tool.

This setup runs **1 FE + 1 BE** for lightweight local development, with a commented production-ready configuration (3 FE + 3 BE) built into the same files.

## Architecture

| Component | Role | Description |
|-----------|------|-------------|
| **FE (Frontend)** | Query engine + metadata | Parses SQL, plans queries, manages metadata, serves the Web UI |
| **BE (Backend)** | Storage + compute | Stores data, executes query fragments, handles compaction |

In production, you run 3+ FE nodes (1 master + followers) for metadata HA, and 3+ BE nodes for data replication.

## Prerequisites

### 1. Docker & Docker Compose

```bash
docker --version    # 20.10+
docker compose version  # v2.0+
```

### 2. Host kernel setting (required)

`vm.max_map_count` is a Linux kernel parameter that limits how many memory-mapped file regions a process can have. Doris BE maps tablet data files (segments, indexes) into memory for fast reads — even a small dataset can create thousands of mappings. The Linux default (65,536) is far too low; Doris requires at least **2,000,000**.

This is a **one-time host-level setting**. It cannot be configured inside Docker. Without it, BE will refuse to start.

```bash
# Check current value
sysctl vm.max_map_count

# Set it (required: >= 2000000)
sudo sysctl -w vm.max_map_count=2000000

# Persist across reboots
echo "vm.max_map_count=2000000" | sudo tee -a /etc/sysctl.conf
```

### 3. Copy environment file

```bash
cp .env.example .env
```

## Quick start

```bash
# Start the cluster
docker compose up -d

# Check status
docker compose ps

# View logs
docker compose logs -f doris-fe
docker compose logs -f doris-be
```

Wait ~60-90 seconds for both services to become healthy, then connect.

## Connecting

### MySQL client

```bash
mysql -h 127.0.0.1 -P 9030 -u root -p
```

If you don't have `mysql` installed locally, use the one inside the FE container:

```bash
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root -p
```

> Enter the password set in `.env` (`DORIS_ROOT_PASSWORD`).

### Web UI

Open [http://localhost:8030](http://localhost:8030) in your browser.

> **Note:** The Web UI (port 8030) does **not** enforce authentication — this is by design in Doris. It's an internal admin interface for monitoring cluster status, query profiles, and metadata. The `DORIS_ROOT_PASSWORD` only applies to the MySQL protocol (port 9030). This is fine for local dev since the port is only on localhost. In production, restrict access via firewall or reverse proxy.

### DBeaver

**Option 1: MySQL driver**

1. **New Database Connection** > select **MySQL**
2. Fill in:
   - **Host:** `127.0.0.1`
   - **Port:** `9030`
   - **Database:** *(leave empty or enter a database name)*
   - **Username:** `root`
   - **Password:** value of `DORIS_ROOT_PASSWORD` from `.env`
3. Click **Driver properties** tab and set:
   - `allowPublicKeyRetrieval` = `true`
   - `useSSL` = `false`
4. Click **Test Connection**, then **Finish**

> If you get `Communications link failure`, the MySQL 8 driver may not work with Doris. Try Option 2.

**Option 2: Generic JDBC (if MySQL driver fails)**

1. **New Database Connection** > select **Generic JDBC**
2. Fill in:
   - **JDBC URL:** `jdbc:mysql://127.0.0.1:9030/`
   - **Driver class:** `com.mysql.jdbc.Driver`
   - **Username:** `root`
   - **Password:** value of `DORIS_ROOT_PASSWORD` from `.env`
3. Click **Test Connection**, then **Finish**

### JDBC (Python, Java, etc.)

```
jdbc:mysql://127.0.0.1:9030/<database>
```

Any MySQL-compatible driver works: PyMySQL, mysql-connector-python, JDBC, etc.

## Directory structure

```
apache-doris/
├── docker-compose.yml   # Service definitions (1 FE + 1 BE active, 3+3 commented)
├── .env                 # Environment variables (ports, image tags, password)
├── .env.example         # Template for .env
├── .gitignore           # Ignores .env
├── conf/
│   ├── fe.conf          # FE configuration (JVM, connections, metadata)
│   └── be.conf          # BE configuration (JVM, memory, compaction, buffer)
├── initdb.d/
│   └── 01_create_databases.sql  # Creates databases and users on first startup
└── README.md            # This file
```

## Environment variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `FE_IMAGE` | `apache/doris:fe-3.0.3` | FE Docker image |
| `BE_IMAGE` | `apache/doris:be-3.0.3` | BE Docker image |
| `FE_QUERY_PORT` | `9030` | MySQL protocol port |
| `FE_HTTP_PORT` | `8030` | FE Web UI port |
| `FE_EDIT_LOG_PORT` | `9010` | FE inter-node replication port |
| `BE_HEARTBEAT_PORT` | `9050` | BE heartbeat port |
| `BE_WEBSERVER_PORT` | `8040` | BE HTTP status port |
| `DORIS_ROOT_PASSWORD` | *(empty)* | Root password. Set for production. |

### Changing the Doris version

Edit `.env`:

```bash
# Current stable
FE_IMAGE=apache/doris:fe-3.0.3
BE_IMAGE=apache/doris:be-3.0.3
```

Then recreate containers:

```bash
docker compose down
docker compose up -d
```

## Configuration files

Both `conf/fe.conf` and `conf/be.conf` are mounted into the containers. Every setting has a local dev value active and a production value commented below it.

Settings can also be changed at runtime without restart:

```sql
-- FE settings
ADMIN SET FRONTEND CONFIG ("key" = "value");
SHOW FRONTEND CONFIG LIKE "%key%";

-- BE settings
ADMIN SET BACKEND CONFIG ("key" = "value");
SHOW BACKEND CONFIG LIKE "%key%";
```

> **Note:**
> - **File permissions:** Make sure the user running Docker has read access to the `conf/` directory.
> - **Ports and `priority_networks`** are intentionally excluded from the config files. The Doris entrypoint handles these automatically based on the container's IP. Do not add port definitions or `priority_networks` manually — the entrypoint appends `priority_networks` on first startup and skips it on subsequent restarts.
> - **Ports — `.env` vs container:** The `.env` ports (e.g. `FE_QUERY_PORT=9030`) control the **host-side** mapping only. The container listens on the default ports internally. Only change `.env` if you have a port conflict on your host.

### FE config (conf/fe.conf)

| Setting | Local dev | Production | What it does |
|---------|-----------|------------|--------------|
| `JAVA_OPTS_FOR_JDK_17` (Xmx) | 1 GB | 16 GB | JVM heap size. FE stores metadata in memory. |
| `qe_max_connection` | 256 | 2048 | Max concurrent client connections |
| `max_running_txn_num_per_db` | 100 | 2000 | Max concurrent transactions per database |
| `edit_log_roll_num` | 50000 | 50000 | Metadata journal entries before checkpoint |
| `meta_delay_toleration_second` | 300 | 300 | Max metadata lag for follower FEs (seconds) |
| `storage_flood_stage_usage_percent` | 95 | 95 | Disk usage % before rejecting writes |

### BE config (conf/be.conf)

| Setting | Local dev | Production | What it does |
|---------|-----------|------------|--------------|
| `JAVA_OPTS_FOR_JDK_17` (Xmx) | 512 MB | 4 GB | JVM heap for Java UDFs and internal operations |
| `mem_limit` | 80% | 90% | % of container memory BE can use for queries/cache |
| `max_base_compaction_threads` | 2 | 4 | Threads for base compaction (merges all rowsets) |
| `max_cumu_compaction_threads` | 2 | -1 (auto) | Threads for cumulative compaction (merges recent) |
| `compaction_task_num_per_disk` | 2 | 4 | Concurrent compaction tasks per HDD |
| `compaction_task_num_per_fast_disk` | 4 | 8 | Concurrent compaction tasks per SSD |
| `write_buffer_size` | 64 MB | 200 MB | Buffer size before flushing imported data to disk |
| `sys_log_roll_mode` | 512 MB | 1 GB | Max size per log file |
| `sys_log_roll_num` | 5 | 10 | Number of log files to retain |

## Init scripts (initdb.d/)

The `initdb.d/` folder is mounted into the BE container. On **first startup only**, after BE registers with FE, it automatically executes files in alphabetical order:

| File type | Behavior |
|-----------|----------|
| `.sql` | Executed against Doris via MySQL protocol |
| `.sh` | Executed as a shell script |
| `.sql.gz` | Decompressed, then executed as SQL |

The included `initdb.d/01_create_databases.sql` creates `example_db` and a sample `dev` user. Modify or remove it for your own project.

To add your own, drop files with a numbered prefix for ordering:

```
initdb.d/
├── 01_create_databases.sql   # included (databases + users)
├── 02_more_databases.sql     # your own
└── 03_more_users.sql         # your own
```

If the folder is empty, nothing happens.

> **Important:** Init scripts run before BE is fully alive. Only `CREATE DATABASE` and user management work reliably. `CREATE TABLE` will fail because it needs an available BE. Create tables manually after the cluster is healthy, or use a shell script with a sleep/retry loop.

> Use `"replication_num" = "1"` with 1 BE. With 3 BEs, use `"3"` (the production default).

## Scaling to production-like setup

### Step 1: Uncomment extra nodes in docker-compose.yml

Uncomment `doris-fe-2`, `doris-fe-3`, `doris-be-2`, `doris-be-3` and their volumes at the bottom of the file.

### Step 2: Uncomment resource limits

Uncomment the `deploy.resources` blocks in each service.

### Step 3: Update config files

In `conf/fe.conf` and `conf/be.conf`, comment the local dev values and uncomment the production values. Each production line is marked with `# Production:`.

### Step 4: Recreate

```bash
docker compose down
docker compose up -d
```

## Common operations

### Check cluster status

```sql
-- Connected via mysql client
SHOW FRONTENDS\G
SHOW BACKENDS\G
```

### Create a database and table

```sql
CREATE DATABASE my_db;
USE my_db;

CREATE TABLE users (
    id BIGINT NOT NULL,
    name VARCHAR(128),
    created_at DATETIME
)
UNIQUE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 4
PROPERTIES("replication_num" = "1");
```

### Data models

Doris supports three table models:

| Model | Key clause | Use case |
|-------|-----------|----------|
| **Duplicate** | `DUPLICATE KEY(...)` | Raw logs, events — keeps all rows |
| **Unique** | `UNIQUE KEY(...)` | Dimension tables — upserts by key |
| **Aggregate** | `AGGREGATE KEY(...)` | Pre-aggregated metrics — SUM, MAX, MIN, etc. |

### Load data

```sql
-- Stream Load (small files, via HTTP)
curl -u root:$DORIS_ROOT_PASSWORD -T data.csv \
  -H "format: csv" \
  -H "column_separator: ," \
  http://127.0.0.1:8030/api/my_db/my_table/_stream_load

-- Insert
INSERT INTO my_table VALUES (1, 'Alice', '2024-01-01 00:00:00');

-- Load from S3 (Broker Load)
LOAD LABEL my_db.load_job_1 (
    DATA INFILE("s3://bucket/path/data.parquet")
    INTO TABLE my_table
    FORMAT AS "parquet"
)
WITH S3 (
    "AWS_ENDPOINT" = "s3.amazonaws.com",
    "AWS_ACCESS_KEY" = "...",
    "AWS_SECRET_KEY" = "...",
    "AWS_REGION" = "us-east-1"
);
```

### Monitoring

| Endpoint | URL | Description |
|----------|-----|-------------|
| FE Web UI | http://localhost:8030 | Query profiles, metadata, cluster status |
| BE Status | http://localhost:8040 | BE metrics, tablet info, compaction status |

### Stop and clean up

```bash
# Stop containers (keeps data)
docker compose down

# Stop and remove all data
docker compose down -v
```

## Ports reference

| Port | Protocol | Component | Purpose |
|------|----------|-----------|---------|
| 9030 | MySQL | FE | SQL queries (MySQL client / JDBC) |
| 8030 | HTTP | FE | Web UI, REST API, Stream Load |
| 9010 | TCP | FE | Edit log replication (inter-FE) |
| 9020 | Thrift | FE | Internal RPC |
| 8070 | gRPC | FE | Arrow Flight SQL |
| 9050 | TCP | BE | Heartbeat |
| 8040 | HTTP | BE | Status page, metrics |
| 8060 | gRPC | BE | BRPC (inter-BE data exchange) |
| 9060 | Thrift | BE | BE port (FE-to-BE communication) |

## Known issues and workarounds

### Swap check — BE crashes with "Disable swap memory"

Doris BE's `start_be.sh` **hardcodes** a swap check that exits if the host has swap enabled. There is no config flag to disable it. This affects all versions (2.1.x, 3.0.x).

**Workaround:** The `docker-compose.yml` overrides the BE entrypoint with an inline one-liner that creates a fake `swapon` command (reports no swap) before calling the original entrypoint. This is transparent and has no side effects.

If your host has swap disabled, you can remove the `entrypoint` line from the BE service and it will use the default.

### FE_SERVERS and BE_ADDR require IP addresses, not hostnames

The Doris entrypoint scripts validate `FE_SERVERS` and `BE_ADDR` with a regex that **only accepts IP addresses** (e.g. `10.10.80.2`), not Docker hostnames (e.g. `doris-fe`). This is why the `docker-compose.yml` uses static IPs from the `10.10.80.0/24` subnet and references them directly in environment variables.

If you change the subnet in `docker-compose.yml`, you must also update the IPs in `FE_SERVERS` and `BE_ADDR` for every service.

### Network subnet overlap

Docker will fail with `Pool overlaps with other one on this address space` if the subnet (`10.10.80.0/24`) conflicts with an existing Docker network. Check existing subnets:

```bash
docker network inspect $(docker network ls -q) 2>/dev/null | grep Subnet
```

Then change the subnet and all IPs in `docker-compose.yml` to a free range.

### Init scripts cannot CREATE TABLE

The `initdb.d/` scripts run right after BE registers with FE but **before BE reports as alive**. At that point, FE shows 0 available backends, so any `CREATE TABLE` statement fails with:

```
replication num should be less than the number of available backends
```

**Workaround:** Only use `CREATE DATABASE` and user management in init scripts. Create tables manually after the cluster is fully healthy (`docker compose ps` shows both services as `healthy`).

### Config files — `priority_networks` appending

The Doris entrypoint automatically appends `priority_networks = <subnet>` to both `fe.conf` and `be.conf` on startup. Since these files are bind-mounted from the host, the change persists. The entrypoint checks if the line already exists before appending, so it only happens **once** — subsequent restarts do not add duplicates.

This is why `priority_networks` and port definitions are intentionally excluded from the config files. Do not add them manually.

### DORIS_ROOT_PASSWORD env var does not set the password

The `DORIS_ROOT_PASSWORD` environment variable in the official Docker image is unreliable — it does not always set the root password. Connections from inside the FE container (`localhost`) also bypass authentication entirely — this is normal Doris behavior.

**Workaround:** The BE entrypoint in `docker-compose.yml` includes a background job that runs `ALTER USER` after 90 seconds (when FE is ready), using the `DORIS_ROOT_PASSWORD` value from `.env`. The password is enforced for external connections (DBeaver, JDBC, any remote client).

### Web UI has no authentication

The Web UI on port 8030 does not enforce authentication. `DORIS_ROOT_PASSWORD` only protects the MySQL protocol (port 9030). This is by design in Doris. For local dev this is fine. In production, restrict port 8030 via firewall or reverse proxy.

## Troubleshooting

### BE fails to start: "vm.max_map_count" error

```bash
sudo sysctl -w vm.max_map_count=2000000
echo "vm.max_map_count=2000000" | sudo tee -a /etc/sysctl.conf
```

### "Failed to find enough host" when creating tables

You're using `"replication_num" = "3"` with fewer than 3 BE nodes. Use `"1"` for single-BE setup.

### FE health check keeps failing

Check FE logs for JVM OOM. Increase `Xmx` in `conf/fe.conf` or raise the container memory limit.

```bash
docker compose logs doris-fe | tail -50
```

### BE goes offline after restart

Doris stores BE addresses by IP. The static IPs in `docker-compose.yml` (`10.10.80.x`) prevent this. If you changed the network config, make sure IPs are stable.

### Slow queries

```sql
-- Check query profile
SET enable_profile = true;
SELECT ...;
SHOW QUERY PROFILE "/query_id"\G

-- Check compaction status (too many rowsets = slow reads)
SHOW TABLET FROM my_table;
```

### View logs

```bash
# FE logs
docker compose logs doris-fe
docker exec doris-fe cat /opt/apache-doris/fe/log/fe.warn.log | tail -50

# BE logs
docker compose logs doris-be
docker exec doris-be cat /opt/apache-doris/be/log/be.WARNING | tail -50
```
