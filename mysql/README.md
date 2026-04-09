# MySQL

The world's most popular open-source relational database — battle-tested, well-documented, and supported by every ORM, BI tool, and cloud provider.

This is a **lightweight, single-node** setup with production-ready container settings (tuned `mysqld` flags via the `command:` block, persistent volume, healthcheck, restart policy, binary logging enabled for PITR/replication).

## Services

| Service | Port | Description |
|---------|------|-------------|
| MySQL | 3306 | Standard MySQL wire protocol — `mysql` CLI, JDBC, every ORM |

## Quick Start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. Start the server:

```bash
docker compose up -d
```

3. Wait ~30 seconds for the healthcheck to pass, then connect:

```bash
docker exec -it mysql mysql -umysql -pmysql app
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `MYSQL_IMAGE` | Server Docker image | `mysql:8.4` |
| `MYSQL_ROOT_PASSWORD` | Root password applied on first startup | `root` |
| `MYSQL_DATABASE` | Database created on first startup | `app` |
| `MYSQL_USER` | Application user created on first startup | `mysql` |
| `MYSQL_PASSWORD` | Password for `MYSQL_USER` | `mysql` |
| `MYSQL_PORT` | Host port for the MySQL protocol | `3306` |

> **Credentials are set on first startup only.** If you change `MYSQL_ROOT_PASSWORD` or `MYSQL_PASSWORD` after the data volume exists, the new values are ignored. Either `docker compose down -v` to wipe and re-init, or change them from inside a session with `ALTER USER 'mysql'@'%' IDENTIFIED BY 'new-password'; FLUSH PRIVILEGES;`.

### Tuning `mysqld`

Runtime settings are passed as flags in [docker-compose.yml](docker-compose.yml). Defaults target a small/medium host (≈2 GB RAM available to MySQL):

| Setting | Default | Notes |
|---|---|---|
| `max_connections` | `200` | Use a pooler (ProxySQL) before raising this |
| `innodb_buffer_pool_size` | `1G` | Rule of thumb: 50–70% of RAM on a dedicated host |
| `innodb_log_file_size` | `256M` | Larger = better write throughput, longer crash recovery |
| `innodb_flush_log_at_trx_commit` | `1` | Full ACID. Set to `2` for ~2x writes if you can tolerate ≤1s loss on host crash |
| `innodb_flush_method` | `O_DIRECT` | Avoids double-buffering on Linux |
| `innodb_io_capacity` | `2000` | SSD baseline; raise for NVMe |
| `binlog_format` | `ROW` | Required for safe replication and CDC (Debezium, Maxwell) |
| `binlog_expire_logs_seconds` | `604800` | 7 days of binlogs retained |
| `sync_binlog` | `1` | Full durability. Set to `0` for ~2x writes if you can tolerate replica drift on crash |
| `slow_query_log` | `1` | Logs queries slower than `long_query_time` |
| `long_query_time` | `0.5` | Log queries slower than 500 ms |
| `sql_mode` | `STRICT_TRANS_TABLES,...` | Strict mode — invalid data raises errors instead of being silently truncated |

## Connecting

### `mysql` CLI (inside the container)

```bash
docker exec -it mysql mysql -umysql -pmysql app
```

### `mysql` CLI (from the host)

```bash
mysql -h 127.0.0.1 -P 3306 -umysql -pmysql app
```

### JDBC

```
jdbc:mysql://127.0.0.1:3306/app
```

### DBeaver

1. **New Database Connection** > select **MySQL**
2. Fill in:
   - **Server Host:** `127.0.0.1`
   - **Port:** `3306`
   - **Database:** `app`
   - **Username:** `mysql`
   - **Password:** value of `MYSQL_PASSWORD` from `.env`
3. Click **Test Connection**, then **Finish**

> If DBeaver prompts to download the MySQL driver, accept. For MySQL 8.x, the standard `Connector/J` driver works.

### Python

```python
# PyMySQL (pure Python, no system deps)
import pymysql
conn = pymysql.connect(host="127.0.0.1", port=3306,
                       user="mysql", password="mysql", database="app")
with conn.cursor() as cur:
    cur.execute("SELECT VERSION()")
    print(cur.fetchone())

# SQLAlchemy
from sqlalchemy import create_engine, text
engine = create_engine("mysql+pymysql://mysql:mysql@127.0.0.1:3306/app")
with engine.connect() as conn:
    print(conn.execute(text("SELECT VERSION()")).scalar())
```

## Init scripts (initdb.d/)

The `initdb.d/` folder is mounted at `/docker-entrypoint-initdb.d/` in the container. On **first startup only** — when the data directory is empty — the entrypoint runs every `*.sql`, `*.sql.gz`, and `*.sh` in alphabetical order.

Every template in this repo follows the same three-file layout:

| File | Purpose |
|---|---|
| [`01-infra-setup.sh`](initdb.d/01-infra-setup.sh) | Creates the `bronze`, `silver`, `gold` databases and the data-engineering service accounts. Passwords come from env vars, are escaped, and piped over stdin (never on the command line). |
| [`02-logical-setup.sql`](initdb.d/02-logical-setup.sql) | No-op for MySQL — there is no schema layer between database and table, so the layers *are* databases. Kept for layout consistency with Postgres/MSSQL. |
| [`03-governance.sql`](initdb.d/03-governance.sql) | Grants `transform_user` full privileges and `read_user` SELECT on all three layers. MySQL's `db.*` wildcard covers future tables automatically. |

### Accounts and layers

| Account | Privileges | Notes |
|---|---|---|
| `root` | Superuser | From `MYSQL_ROOT_PASSWORD` |
| `${MYSQL_USER}` (default `mysql`) | All privileges on `${MYSQL_DATABASE}` (default `app`) | Created by the entrypoint from env vars — the legacy app user |
| `transform_user` | `ALL PRIVILEGES` on `bronze.*`, `silver.*`, `gold.*` | Full DDL + DML on all three layers |
| `read_user` | `SELECT` on `bronze.*`, `silver.*`, `gold.*` | Read-only; covers existing + future tables |

The medallion layers (**bronze** raw, **silver** cleaned, **gold** curated) live as standalone databases *in addition to* the pre-existing `${MYSQL_DATABASE}`. Postgres and MSSQL can nest them as schemas under one database; MySQL cannot.

Set `TRANSFORM_USER_PASSWORD` and `READ_USER_PASSWORD` in `.env` before the first `docker compose up -d`. Avoid single quotes in the values.

### When init scripts run

The MySQL entrypoint runs every `*.sh`, `*.sql`, and `*.sql.gz` in `initdb.d/` **once**, on the very first boot against an empty data directory. After that, the volume is marked as initialized and the scripts are never touched again.

| Action | Volume state | Init runs? |
|---|---|---|
| First `docker compose up -d` | empty | **yes** |
| `docker compose restart` | populated | no |
| `docker compose down` then `up -d` | populated | no |
| `docker compose down -v` then `up -d` | wiped → empty | **yes** |
| Editing a file in `initdb.d/`, then `up -d` | populated | no — the file change is irrelevant until the volume is wiped |

Treat `initdb.d/` as **bootstrap, not migrations**. For ongoing schema changes, use a real migration tool (Flyway, Liquibase, Alembic, golang-migrate, dbmate).

To apply a script change without wiping data, pipe the file through `mysql` manually:

```bash
# Re-apply the grants (idempotent — safe to re-run)
docker exec -i mysql mysql -uroot -proot < initdb.d/03-governance.sql
```

If you edit `01-infra-setup.sh` or `02-logical-setup.sql` and want the changes reflected without wiping data, you'll need to run the equivalent SQL by hand (the `.sh` file isn't something you can pipe through `mysql` — read it, adapt the inline SQL, and execute it as `root`).

## Data persistence

| Volume | Mount | Contains |
|--------|-------|----------|
| `mysql-data` | `/var/lib/mysql` | InnoDB tablespaces, binary logs, system tables — **the database** |

```bash
# Stop containers (keeps data)
docker compose down

# Stop and wipe everything
docker compose down -v
```

### Backups

Logical dump (portable, slow for large DBs):

```bash
docker exec -t mysql mysqldump -uroot -proot \
    --single-transaction --routines --triggers --events \
    app > app.sql
```

Restore:

```bash
docker exec -i mysql mysql -uroot -proot app < app.sql
```

Physical backup with `xtrabackup` (fast, suitable for PITR with binlog replay) — requires the `percona-xtrabackup` image; see the [Percona docs](https://docs.percona.com/percona-xtrabackup/8.0/index.html).

### Point-in-time recovery

Binary logging is enabled (`--log-bin=mysql-bin`), so PITR is possible:

```bash
# List binlogs
docker exec -t mysql mysql -uroot -proot -e "SHOW BINARY LOGS;"

# Replay a binlog from a specific position
docker exec -t mysql mysqlbinlog --start-datetime="2026-04-08 10:00:00" \
    /var/lib/mysql/mysql-bin.000001 | docker exec -i mysql mysql -uroot -proot app
```

## Common operations

### Server status

```sql
SELECT VERSION();
SHOW ENGINE INNODB STATUS\G
SHOW PROCESSLIST;
SELECT table_schema,
       ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
GROUP BY table_schema;
```

### Create a table

```sql
CREATE TABLE users (
    id          BIGINT NOT NULL AUTO_INCREMENT,
    email       VARCHAR(255) NOT NULL,
    created_at  TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY users_email_uk (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

### Top slow queries (from Performance Schema)

```sql
SELECT
    ROUND(SUM_TIMER_WAIT / 1e12, 2)  AS total_s,
    COUNT_STAR                       AS calls,
    ROUND(AVG_TIMER_WAIT / 1e9, 2)   AS avg_ms,
    DIGEST_TEXT
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;
```

### InnoDB buffer pool hit ratio

```sql
SELECT
    ROUND(
      (1 - (
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status
            WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads')
       /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status
            WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')
      )) * 100, 4
    ) AS hit_ratio_pct;
```

Aim for above `99%` on read-heavy workloads.

### Create a read-only user

```sql
CREATE USER 'reader'@'%' IDENTIFIED BY 'reader-password';
GRANT SELECT ON app.* TO 'reader'@'%';
FLUSH PRIVILEGES;
```

## Troubleshooting

### Authentication failed / password doesn't work

`MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD` only take effect on an empty data volume. If you changed them afterwards, either wipe the volume (`down -v`) or run `ALTER USER ... IDENTIFIED BY ...` from an existing session.

### `ERROR 2059 (HY000): Authentication plugin 'caching_sha2_password' cannot be loaded`

Older MySQL clients (<8.0) don't support the default auth plugin. Either upgrade your client, or create the user with the legacy plugin:

```sql
ALTER USER 'mysql'@'%' IDENTIFIED WITH mysql_native_password BY 'mysql';
```

### Init script didn't run

Init scripts only run on a **fresh** `mysql-data` volume. Run `docker compose down -v` then `up -d` to re-init, or apply the SQL manually.

### `ERROR 1040 (HY000): Too many connections`

You've hit `max_connections`. Either raise it in the `command:` block (costs memory per connection — roughly 256–512 KB each), or — the correct fix — put a pooler like ProxySQL in front.

### Container takes a long time to become healthy

First startup runs `initdb.d/` against a fresh data directory and is slower (~20–30 s). Subsequent starts are quick. Check logs if it's stuck:

```bash
docker compose logs -f mysql
```

### View server logs

```bash
docker compose logs mysql | tail -100
docker compose logs -f mysql
```

The slow query log is written inside the container at `/var/lib/mysql/mysql-slow.log`:

```bash
docker exec -it mysql tail -f /var/lib/mysql/mysql-slow.log
```
