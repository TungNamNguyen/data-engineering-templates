# Apache Doris

Apache Doris is a high-performance, real-time analytical database. It uses a MySQL-compatible protocol, so you can connect with any MySQL client, JDBC driver, or BI tool.

This template runs **1 FE + 1 BE** with production-grade container settings (persistent volumes, healthchecks, ulimits, restart policy, tuned `fe.conf`/`be.conf`), and carries a commented **3 FE + 3 BE** layout in the same files.

> **What "production" means for Doris.** The [official sizing guide](https://doris.apache.org/docs/install/preparation/cluster-planning/) classifies 1 FE + 1 BE as a *development and test* topology: one BE means one data replica, so a lost disk is lost data, and one FE means no metadata failover. Production is **≥ 3 FE Followers + ≥ 3 BE** with `replication_num = 3`. The container-level settings here are production-grade in both topologies; the node count is what you scale when you go live — see [Scaling to production](#scaling-to-production).

There is no init-script mechanism — databases, users, and tables are yours to create (see [First-time setup](#first-time-setup)).

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

### 2. Host requirements

These are host-level settings from the Doris [OS Checking](https://doris.apache.org/docs/install/preparation/os-checking/) and [Environment Checking](https://doris.apache.org/docs/3.x/install/preparation/env-checking/) guides. None of them can be set from inside a container.

| Setting | Dev | Production | Why |
|---|---|---|---|
| CPU supports **AVX2** | required | required | The official image is built with AVX2 vectorization; BE crashes on the first query without it |
| `vm.max_map_count ≥ 2000000` | required | required | BE mmaps every tablet segment; the kernel default (65,536) is far too low and BE refuses to start |
| **Swap disabled** | optional (see below) | required | The kernel may page BE memory out under pressure, which wrecks query latency and can trip the memory tracker |
| Transparent Huge Pages = `madvise` | recommended | required | Avoids latency spikes and memory fragmentation from THP compaction |
| `net.ipv4.tcp_abort_on_overflow = 1` | optional | recommended | Fail fast on listen-queue overflow instead of silently dropping SYNs |
| CPU governor = `performance` | optional | recommended | Prevents frequency scaling from adding query latency |
| Open file limit `nofile = 1000000` | done by compose | done by compose | Set via `ulimits:` in `docker-compose.yml` |
| Clock sync (NTP) | n/a | required with multiple hosts | FE metadata sync tolerates < 5 s skew between FE nodes |

```bash
# AVX2 — must print at least one line
grep -m1 -o avx2 /proc/cpuinfo

# Memory-map limit (required)
sudo sysctl -w vm.max_map_count=2000000
echo "vm.max_map_count=2000000" | sudo tee -a /etc/sysctl.conf

# Swap (required in production; see note)
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

# Transparent Huge Pages
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# TCP overflow behaviour
sudo sysctl -w net.ipv4.tcp_abort_on_overflow=1
echo "net.ipv4.tcp_abort_on_overflow=1" | sudo tee -a /etc/sysctl.conf

# CPU governor (skip on VMs / cloud instances that do not expose it)
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

> **Swap and the BE entrypoint shim.** BE's `start_be.sh` refuses to start if the host has swap enabled. For dev convenience, `docker-compose.yml` overrides the BE entrypoint with a fake `swapon` that hides swap from that check — so BE starts on a laptop with swap on. That shim **bypasses the check, it does not fix the problem**: in production, disable swap on the host as above. Once swap is off you can delete the `entrypoint:` block from the BE service and use the image default.

#### Hardware sizing (from the docs)

| | Dev / test minimum | Production recommended |
|---|---|---|
| FE | 8 cores, 8 GB, SSD 10 GB+ | 16+ cores, 64 GB+, SSD 100 GB+ |
| BE | 8 cores, 16 GB, 50 GB+ | 16+ cores, 64 GB+, SSD, 3 nodes |
| Memory rule | — | BE: cores × 8 GB; FE ≥ 16 GB |
| BE disk | — | data volume × 3 replicas × 1.4 (compaction headroom) |

The commented `deploy.resources` blocks in `docker-compose.yml` (8 CPU / 16 GB) are container caps, not sizing advice — raise them to match your host.

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

> A fresh cluster has **no root password** — press Enter at the prompt (or drop `-p`). Set one right away; see [First-time setup](#first-time-setup).

### Web UI

Open [http://localhost:8030](http://localhost:8030) in your browser.

> **Note:** The Web UI (port 8030) does **not** enforce authentication — this is by design in Doris. It's an internal admin interface for monitoring cluster status, query profiles, and metadata. The root password only applies to the MySQL protocol (port 9030). That is why 8030 (and BE's 8040) are bound to `127.0.0.1` on the host by default via `ADMIN_BIND_ADDR`. If you need them reachable from other machines (e.g. Stream Load from an ETL host), set `ADMIN_BIND_ADDR=0.0.0.0` and put a firewall or authenticating reverse proxy in front.

### DBeaver

**Option 1: MySQL driver**

1. **New Database Connection** > select **MySQL**
2. Fill in:
   - **Host:** `127.0.0.1`
   - **Port:** `9030`
   - **Database:** *(leave empty or enter a database name)*
   - **Username:** `root`
   - **Password:** the root password you set in [First-time setup](#first-time-setup)
3. Click **Driver properties** tab and set:
   - `allowPublicKeyRetrieval` = `true` — Doris doesn't send a public key during handshake like MySQL does; without this the driver refuses to send credentials
   - `useSSL` = `false` — Doris does not support SSL/TLS connections; the driver will fail the handshake if it tries to negotiate SSL
4. Click **Test Connection**, then **Finish**

> Use `127.0.0.1` instead of `localhost`. Some MySQL drivers treat `localhost` as a Unix socket connection, which fails since Doris runs inside a container.

> If you get `Communications link failure`, the MySQL 8 driver may not work with Doris. Try Option 2.

**Option 2: Generic JDBC (if MySQL driver fails)**

1. **New Database Connection** > select **Generic JDBC**
2. Fill in:
   - **JDBC URL:** `jdbc:mysql://127.0.0.1:9030/`
   - **Driver class:** `com.mysql.jdbc.Driver`
   - **Username:** `root`
   - **Password:** the root password you set in [First-time setup](#first-time-setup)
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
├── .env                 # Environment variables (ports, image tags)
├── .env.example         # Template for .env
├── .gitignore           # Ignores .env
├── conf/
│   ├── fe.conf          # FE configuration (JVM, connections, metadata)
│   └── be.conf          # BE configuration (JVM, memory, compaction, buffer)
└── README.md            # This file
```

## Environment variables (.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `FE_IMAGE` | `apache/doris:fe-3.0.8` | FE Docker image |
| `BE_IMAGE` | `apache/doris:be-3.0.8` | BE Docker image |
| `FE_QUERY_PORT` | `9030` | MySQL protocol port |
| `FE_HTTP_PORT` | `8030` | FE Web UI port |
| `FE_EDIT_LOG_PORT` | `9010` | FE inter-node replication port |
| `BE_HEARTBEAT_PORT` | `9050` | BE heartbeat port |
| `BE_WEBSERVER_PORT` | `8040` | BE HTTP status port |
| `ADMIN_BIND_ADDR` | `127.0.0.1` | Host interface for the unauthenticated admin ports (8030, 8040). `0.0.0.0` exposes them to the network — firewall or reverse-proxy them if you do. |

> There is no root-password variable. The image's `DORIS_ROOT_PASSWORD` hook is unreliable, so the password is set once by hand after first startup — see [First-time setup](#first-time-setup).

### Changing the Doris version

Edit `.env`:

```bash
# Latest 3.0.x patch release (bug fixes only — safe to move between patches)
FE_IMAGE=apache/doris:fe-3.0.8
BE_IMAGE=apache/doris:be-3.0.8
```

Keep FE and BE on the **same** tag. Moving to a new minor/major line (3.1, 4.0) is an upgrade, not a tag swap — read the release notes and upgrade FE before BE per the [upgrade guide](https://doris.apache.org/docs/admin-manual/cluster-management/upgrade/).

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
> - **Ports** are intentionally excluded from the config files — the container listens on the defaults and the Doris entrypoint derives everything from the container's IP. **`priority_networks`** is appended by the entrypoint every time it initializes an empty meta/storage directory (no duplicate check — see [Known issues](#config-files--priority_networks-appending)); the committed value matches the compose subnet, so the duplicates are harmless.
> - **Ports — `.env` vs container:** The `.env` ports (e.g. `FE_QUERY_PORT=9030`) control the **host-side** mapping only. The container listens on the default ports internally. Only change `.env` if you have a port conflict on your host.

### FE config (conf/fe.conf)

| Setting | Local dev | Production | What it does |
|---------|-----------|------------|--------------|
| `lower_case_table_names` | 1 | 1 | Table names stored/compared lowercase (docs recommendation). **Cannot be changed after the cluster is created** — decide before the first `up`. |
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

## First-time setup

Unlike postgres/mysql/clickhouse, this template ships **no `initdb.d/` mechanism** — the Doris image has none built in, and a sidecar that re-runs on every `up` adds more moving parts than it saves. Bootstrap the cluster once by hand after it is healthy. Everything below is persisted in the `doris-fe-meta` volume and survives restarts.

### 1. Set the root password

A fresh cluster starts with a passwordless `root`. Set one before exposing port 9030 beyond localhost:

```bash
docker exec -it doris-fe mysql -h 127.0.0.1 -P 9030 -u root
```

```sql
SET PASSWORD FOR 'root' = PASSWORD('your-strong-password');
```

> Connections from **inside** the FE container bypass authentication, so `docker exec ... mysql` keeps working without `-p` — this is normal Doris behavior. The password is enforced for every external client (DBeaver, JDBC, BI tools).

### 2. Create databases and a service account

Doris follows the MySQL model — there is no schema layer between database and table. Adjust names and privileges to your project:

```sql
CREATE DATABASE IF NOT EXISTS analytics;

CREATE USER IF NOT EXISTS 'app_user' IDENTIFIED BY 'app-password';
GRANT SELECT_PRIV, LOAD_PRIV, ALTER_PRIV, CREATE_PRIV, DROP_PRIV ON analytics.* TO 'app_user';

-- Read-only account for BI tools
CREATE USER IF NOT EXISTS 'read_user' IDENTIFIED BY 'read-password';
GRANT SELECT_PRIV ON analytics.* TO 'read_user';
```

### 3. Create tables

See [Create a database and table](#create-a-database-and-table) below. With a single BE you **must** use `"replication_num" = "1"`; with 3 BEs use `"3"` (the production default).

To keep this reproducible, store your bootstrap SQL in version control and apply it with:

```bash
docker exec -i doris-fe mysql -h 127.0.0.1 -P 9030 -u root < bootstrap.sql
```

## Scaling to production

This is what turns the dev/test topology into the one the Doris docs call production: ≥ 3 FE for metadata HA, ≥ 3 BE for 3-replica storage.

### Step 0: Host checklist

Work through [Host requirements](#2-host-requirements) — in particular disable swap for real and remove the BE `entrypoint:` shim. If the nodes end up on different hosts, make sure NTP is running on all of them.

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
curl -u root:<root-password> -T data.csv \
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

**Dev workaround:** The `docker-compose.yml` overrides the BE entrypoint with an inline one-liner that creates a fake `swapon` command (reports no swap) before calling the original entrypoint. It lets BE start on a workstation with swap on; it does **not** make swap safe for Doris. In production, disable swap on the host (see [Host requirements](#2-host-requirements)) and remove the `entrypoint:` block from the BE service.

### FE_SERVERS and BE_ADDR require IP addresses, not hostnames

The Doris entrypoint scripts validate `FE_SERVERS` and `BE_ADDR` with a regex that **only accepts IP addresses** (e.g. `10.10.80.2`), not Docker hostnames (e.g. `doris-fe`). This is why the `docker-compose.yml` uses static IPs from the `10.10.80.0/24` subnet and references them directly in environment variables.

If you change the subnet in `docker-compose.yml`, you must also update the IPs in `FE_SERVERS` and `BE_ADDR` for every service.

### Network subnet overlap

Docker will fail with `Pool overlaps with other one on this address space` if the subnet (`10.10.80.0/24`) conflicts with an existing Docker network. Check existing subnets:

```bash
docker network inspect $(docker network ls -q) 2>/dev/null | grep Subnet
```

Then change the subnet and all IPs in `docker-compose.yml` to a free range.

### Config files — `priority_networks` appending

The Doris entrypoint (`init_fe.sh` / `init_be.sh`) appends `priority_networks = <subnet>` to `fe.conf` / `be.conf` whenever it initializes an **empty** meta/storage directory — i.e. on the first `up` and after every `docker compose down -v`. It does **not** check whether the line is already there, so a bind-mounted `conf/` collects one duplicate line per re-init. Restarts against an existing volume do not append.

All copies carry the same value (`10.10.80.0/24`, matching the compose subnet), so Doris behaves identically; if the extra lines bother you, delete them — `git checkout -- conf/` restores the committed files. If you change the subnet in `docker-compose.yml`, update the committed `priority_networks` line in both files to match.

### Root password is not set from an env var

The `DORIS_ROOT_PASSWORD` environment variable in the official Docker image is unreliable — it does not always set the root password — so this template does not use it. Set the password once by hand instead ([First-time setup](#first-time-setup)). Connections from inside the FE container (`localhost`) bypass authentication entirely — this is normal Doris behavior.

### Web UI has no authentication

The Web UI on port 8030 does not enforce authentication. The root password only protects the MySQL protocol (port 9030). This is by design in Doris. The template binds 8030 and 8040 to `127.0.0.1` on the host (`ADMIN_BIND_ADDR`); if you expose them, restrict access via firewall or reverse proxy.

## Troubleshooting

### BE fails to start: "vm.max_map_count" error

```bash
sudo sysctl -w vm.max_map_count=2000000
echo "vm.max_map_count=2000000" | sudo tee -a /etc/sysctl.conf
```

### FE stays unhealthy: `The configuration of 'lower_case_table_names' does not support modification`

```
ERROR (stateListener) [Env.checkLowerCaseTableNames()] The configuration of 'lower_case_table_names' does not support modification, the expected value is 0, but the actual value is 1
```

The value in `conf/fe.conf` differs from the one the cluster was created with — Doris stores it in metadata and refuses to start on a mismatch. Either put `fe.conf` back to the original value (`0` if the volume predates this template's `lower_case_table_names = 1`), or wipe the cluster with `docker compose down -v` and start fresh. There is no in-place migration.

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
