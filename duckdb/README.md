# DuckDB

Fast in-process analytical database — columnar, vectorized, zero-config. Think "SQLite for analytics". This template packages it as a **lightweight file-based data warehouse**: one tiny container, one `.duckdb` file on disk, and the `bronze` / `silver` / `gold` medallion layout waiting for you.

DuckDB is not a server. The container is a thin wrapper around the CLI: it bootstraps the schemas on start, then stays up so `docker exec` sessions share the same file.

## Layout

```
duckdb/
├── Dockerfile          # installs the DuckDB CLI on debian:bookworm-slim
├── docker-compose.yml  # bind-mounts ./data, runs init.sql, keeps container alive
├── init.sql            # CREATE SCHEMA bronze / silver / gold  (idempotent)
├── .env.example        # DUCKDB_VERSION, DUCKDB_DB
└── data/               # bind mount — .duckdb file + landing CSV/Parquet/JSON
```

This template intentionally skips the `initdb.d/` three-file convention used by the other DB templates in this repo. Postgres, MySQL, ClickHouse, MSSQL, and Doris need separate files for user creation, schema creation, and grants — DuckDB has no user or grant system, so two of those files would be no-ops. One `init.sql` carries everything DuckDB actually supports.

## Quick Start

```bash
cp .env.example .env
docker compose build
docker compose up -d
docker exec -it duckdb duckdb /data/app.duckdb
```

Inside the shell:

```sql
SELECT version();
SELECT schema_name FROM information_schema.schemata
 WHERE schema_name IN ('bronze','silver','gold');
.quit
```

The `.duckdb` file now lives at `./data/app.duckdb` on the host — ready to be opened by Python, dbt-duckdb, or any other local tool.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DUCKDB_VERSION` | CLI version baked into the image (build arg) | `1.2.2` |
| `DUCKDB_DB` | Database filename inside `./data/` | `app.duckdb` |

Changing `DUCKDB_VERSION` requires `docker compose build`. Changing `DUCKDB_DB` just creates a different file on next start — `init.sql` is idempotent and will re-apply the schemas to it.

## Using it as a DWH

The workflow is **land → bronze → silver → gold**, all driven by SQL against a single file.

**Land** files by dropping them into `./data/` on the host. They appear at `/data/...` inside the container instantly — no copy, no upload.

```bash
cp ~/Downloads/events.parquet duckdb/data/
```

**Ingest into bronze** by reading the files in place — no staging step:

```sql
CREATE OR REPLACE TABLE bronze.events AS
SELECT * FROM read_parquet('/data/events.parquet');

CREATE OR REPLACE TABLE bronze.orders AS
SELECT * FROM read_csv('/data/orders.csv', header = true);
```

**Clean into silver** with ordinary SQL:

```sql
CREATE OR REPLACE TABLE silver.events AS
SELECT id,
       lower(event_type)              AS event_type,
       try_cast(payload AS JSON)      AS payload,
       cast(ingested_at AS TIMESTAMP) AS ingested_at
FROM bronze.events
WHERE id IS NOT NULL;
```

**Curate into gold** as business-ready aggregates:

```sql
CREATE OR REPLACE TABLE gold.daily_event_counts AS
SELECT date_trunc('day', ingested_at) AS day,
       event_type,
       count(*)                       AS n
FROM silver.events
GROUP BY ALL;
```

### Performance knobs

DuckDB autotunes well. These three SETs cover 90% of the tuning you'll want:

```sql
SET memory_limit = '8GB';
SET threads      = 8;
SET preserve_insertion_order = false;   -- faster large INSERTs
```

Apply per session or add them to `init.sql` if you want them baked in.

## Connecting from the host

The `.duckdb` file is a regular file on your host. Any local tool can open it — as long as nothing else holds a write lock.

### Python

```bash
pip install duckdb
```

```python
import duckdb
con = duckdb.connect("data/app.duckdb", read_only=True)
print(con.sql("SELECT * FROM gold.daily_event_counts").df())
```

### dbt

```yaml
# profiles.yml
my_project:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: ./data/app.duckdb
      threads: 4
```

### Concurrency caveat

DuckDB allows **one writer OR many readers** per file, not both. If the container CLI holds the file open for writing, host-side Python must use `read_only=True` or wait.

## Backups

DuckDB is a single file. The simplest backup is a copy — but release write locks first:

```bash
docker compose stop
cp data/app.duckdb data/app.duckdb.$(date +%F)
docker compose start
```

For a version-portable backup that survives DuckDB storage-format upgrades:

```bash
docker exec -i duckdb duckdb /data/app.duckdb \
    -c "EXPORT DATABASE '/data/backup-$(date +%F)' (FORMAT PARQUET);"
```

Round-trip with `IMPORT DATABASE '/data/backup-YYYY-MM-DD';`.

## Production notes

The compose file ships with defense-in-depth defaults that are free (one-liners, no runtime cost):

| Setting | Why |
|---|---|
| `init: true` | Runs tini as PID 1 so signals forward cleanly during the brief `sh -c` window before `exec tail` takes over, and any zombies get reaped. |
| `security_opt: [no-new-privileges:true]` | Blocks privilege escalation via setuid binaries inside the container. |
| `read_only: true` + `tmpfs: /tmp` | Root filesystem is read-only; only `/data` (bind mount) and `/tmp` (tmpfs) are writable. Blocks tamper attacks on the image layer. |
| `stop_grace_period: 5s` | DuckDB CLI has nothing to flush on SIGTERM; the default 10s is wasted wait. |
| `logging.max-size: 10m` + `max-file: 3` | Caps per-container stdout at 30 MB so a chatty query can't fill the host disk. |
| Pinned `DUCKDB_VERSION` + pinned `debian:bookworm-slim` | Reproducible builds across machines. |

Deliberately not included (add these in a `docker-compose.override.yml` when you actually need them):

- **Resource limits (`deploy.resources`)** — host-specific. For a small host:
    ```yaml
    deploy:
      resources:
        limits:
          cpus: "4"
          memory: 8G
    ```
- **Non-root user** — would require UID/GID juggling against the bind mount. The read-only root + `no-new-privileges` cover most of what non-root would buy on a single-tenant workload.
- **Healthcheck** — there is no daemon to probe. A fake healthcheck that always passes is worse than none.
- **Prometheus metrics / logging driver** — plug in whatever you already run (`loki`, `fluentd`, `syslog`) via the `logging.driver` field.

## When to use this template

Good fit:
- Single-node analytical workloads up to a few hundred GB
- File-based ELT with existing CSV / Parquet / JSON
- dbt-duckdb development environment
- Ephemeral DWH in CI

Reach for something else when:
- You need concurrent writers from multiple processes → Postgres / ClickHouse
- You need a wire protocol for BI tools → Postgres / ClickHouse
- Data doesn't fit on one node → ClickHouse / Apache Doris / cloud warehouse

## Troubleshooting

**`IO Error: Could not set lock on file`** — another process has the file open for writing. Close the other session or open the new one with `read_only=True`.

**`./data/` owned by root after first boot** — the container runs as root and writes through the bind mount. `sudo chown -R $USER:$USER data/` once, or run the host-side commands via `docker exec` instead.

**Init didn't pick up my edit to `init.sql`** — it runs every start, but the statements use `IF NOT EXISTS`, so re-runs won't *recreate* existing objects. For destructive changes, drop them manually first.
