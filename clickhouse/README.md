# ClickHouse

High-performance columnar OLAP database for real-time analytics on huge datasets. Speaks its own native protocol and HTTP — almost any client or BI tool can connect.

This is a **lightweight, single-node** setup with production-ready container settings (persistent volumes, healthcheck, ulimits, restart policy).

## Services

| Service | Port | Description |
|---------|------|-------------|
| ClickHouse HTTP | 8123 | HTTP interface — DBeaver, JDBC HTTP, Prometheus `/metrics`, `/ping` |
| ClickHouse Native | 9000 | Native protocol — `clickhouse-client`, native JDBC, highest throughput |

## Quick Start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. Start the server:

```bash
docker compose up -d
```

3. Wait ~15 seconds for the healthcheck to pass, then connect:

```bash
docker exec -it clickhouse clickhouse-client --user default --password
# enter the password from .env
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `CLICKHOUSE_IMAGE` | Server Docker image | `clickhouse/clickhouse-server:24.8` |
| `CLICKHOUSE_DB` | Database created on first startup | `default` |
| `CLICKHOUSE_USER` | Username for the entrypoint | `default` |
| `CLICKHOUSE_PASSWORD` | Password applied on first startup | `clickhouse` |
| `CLICKHOUSE_HTTP_PORT` | Host port for HTTP interface | `8123` |
| `CLICKHOUSE_NATIVE_PORT` | Host port for native protocol | `9000` |

> **Port 9000 conflict with MinIO:** the [`minio/`](../minio/) template in this repo also uses host port `9000`. If you run both at once, change `CLICKHOUSE_NATIVE_PORT` in `.env` to e.g. `9100`.

> **Password is set on first startup only.** If you change `CLICKHOUSE_PASSWORD` after the data volume already exists, the new value is ignored. Either `docker compose down -v` to wipe and re-init, or update the password from inside the server with `ALTER USER default IDENTIFIED BY 'new-password'`.

## Connecting

### clickhouse-client (inside the container)

```bash
docker exec -it clickhouse clickhouse-client --user default --password
```

### HTTP

```bash
# Health check
curl http://localhost:8123/ping

# Query with HTTP Basic auth
curl -u default:clickhouse 'http://localhost:8123/?query=SELECT%20version()'

# POST a query body
echo 'SELECT now(), version()' | \
  curl -u default:clickhouse --data-binary @- http://localhost:8123/
```

### DBeaver

1. **New Database Connection** > select **ClickHouse**
2. Fill in:
   - **Host:** `127.0.0.1`
   - **Port:** `8123` (DBeaver's official driver uses HTTP, not native)
   - **Database:** `default`
   - **Username:** `default`
   - **Password:** value of `CLICKHOUSE_PASSWORD` from `.env`
3. Click **Test Connection**, then **Finish**

### JDBC

```
jdbc:clickhouse://127.0.0.1:8123/default          # HTTP
jdbc:clickhouse://127.0.0.1:9000/default          # Native (clickhouse-jdbc)
```

### Python

```python
# Native protocol (recommended for throughput)
from clickhouse_driver import Client
client = Client(host='127.0.0.1', port=9000, user='default', password='clickhouse')
print(client.execute('SELECT version()'))

# Or HTTP
import clickhouse_connect
client = clickhouse_connect.get_client(host='127.0.0.1', port=8123, username='default', password='clickhouse')
print(client.query('SELECT version()').result_rows)
```

## Init scripts (initdb.d/)

The `initdb.d/` folder is mounted at `/docker-entrypoint-initdb.d/` in the container. On **first startup only** — when `/var/lib/clickhouse` is empty — the entrypoint runs every `*.sql` and `*.sh` in alphabetical order via `clickhouse-client`.

The included [`initdb.d/01_create_database.sql`](initdb.d/01_create_database.sql) creates `example_db` and a sample `events` table:

```sql
CREATE DATABASE IF NOT EXISTS example_db;

CREATE TABLE IF NOT EXISTS example_db.events
(
    event_id    UInt64,
    event_time  DateTime,
    user_id     UInt64,
    event_type  LowCardinality(String),
    payload     String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_type, event_time, user_id)
TTL event_time + INTERVAL 90 DAY;
```

Add your own scripts with a numbered prefix to control order:

```
initdb.d/
├── 01_create_database.sql   # included
├── 02_create_users.sql      # your own
└── 03_seed_data.sql         # your own
```

### When init scripts run

| Action | Volume state | Init runs? |
|---|---|---|
| First `docker compose up -d` | empty | **yes** |
| `docker compose restart` | populated | no |
| `docker compose down` then `up -d` | populated | no |
| `docker compose down -v` then `up -d` | wiped → empty | **yes** |
| Editing the `.sql` file | populated | no — the file change is irrelevant |

Treat `initdb.d/` as **bootstrap, not migrations**. For ongoing schema changes, apply SQL manually or with a real migration tool (Flyway, Liquibase, dbt, golang-migrate).

To apply a script change without wiping data:

```bash
docker exec -i clickhouse clickhouse-client --user default --password \
  < initdb.d/01_create_database.sql
```

## Data persistence

Two named volumes keep state separate:

| Volume | Mount | Contains |
|--------|-------|----------|
| `clickhouse-data` | `/var/lib/clickhouse` | Tables, parts, system tables, metadata — **the database** |
| `clickhouse-logs` | `/var/log/clickhouse-server` | `clickhouse-server.log`, `clickhouse-server.err.log` |

Splitting them lets you back up data without log churn and clear logs without risking the database.

```bash
# Stop containers (keeps data)
docker compose down

# Stop and wipe everything
docker compose down -v
```

## Common operations

### Server status

```sql
SELECT version();
SELECT * FROM system.parts WHERE active LIMIT 10;
SELECT * FROM system.merges;
```

### Create a table

```sql
CREATE DATABASE my_db;

CREATE TABLE my_db.users
(
    id          UInt64,
    name        String,
    created_at  DateTime
)
ENGINE = MergeTree
ORDER BY (created_at, id);
```

### Load data

```sql
-- INSERT
INSERT INTO my_db.users VALUES (1, 'Alice', now());

-- From a CSV file via HTTP
cat data.csv | curl -u default:clickhouse \
  'http://localhost:8123/?query=INSERT%20INTO%20my_db.users%20FORMAT%20CSV' \
  --data-binary @-

-- From S3
INSERT INTO my_db.users
SELECT * FROM s3(
  'https://bucket.s3.amazonaws.com/users.parquet',
  'AWS_KEY', 'AWS_SECRET',
  'Parquet'
);
```

### Inspect query history

```sql
SELECT
    event_time,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read,
    query
FROM system.query_log
WHERE type = 'QueryFinish' AND event_date = today()
ORDER BY event_time DESC
LIMIT 20;
```

## Troubleshooting

### Authentication failed for user 'default'

The password is only applied on first startup of an empty data volume. If you changed `CLICKHOUSE_PASSWORD` after the fact, either wipe the volume (`down -v`) or `ALTER USER default IDENTIFIED BY 'new-password'` from a connected session.

### Init script didn't run

Init scripts only run on a **fresh** `clickhouse-data` volume. Run `docker compose down -v` then `up -d` to re-init, or apply the SQL manually.

### View server logs

```bash
docker compose logs clickhouse | tail -50
docker exec clickhouse tail -100 /var/log/clickhouse-server/clickhouse-server.log
docker exec clickhouse tail -100 /var/log/clickhouse-server/clickhouse-server.err.log
```
