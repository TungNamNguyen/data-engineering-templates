# DuckDB

Fast in-process analytical database — columnar, vectorized, zero-config. Think "SQLite for analytics". This template packages it as a **lightweight file-based data warehouse**: one tiny container, one `.duckdb` file on disk, and the `bronze` / `silver` / `gold` medallion layout waiting for you.

DuckDB is not a server. The container is a thin wrapper around the CLI — it bootstraps the schemas on start, then stays up so `docker exec` sessions share the same file.

## Layout

```
duckdb/
├── Dockerfile          # installs the DuckDB CLI on debian:bookworm-slim
├── docker-compose.yml  # bind-mounts ./data, runs init.sql, keeps container alive
├── init.sql            # CREATE SCHEMA bronze / silver / gold  (idempotent)
├── .env.example        # optional overrides: DUCKDB_VERSION, DUCKDB_DB
└── data/               # bind mount — .duckdb file + landing CSV/Parquet/JSON
```

This template intentionally skips the `initdb.d/` three-file convention used by the other DB templates in this repo. Postgres, MySQL, ClickHouse, MSSQL, and Doris need separate files for user creation, schema creation, and grants — DuckDB has no user or grant system, so two of those files would be no-ops. One `init.sql` carries everything DuckDB actually supports.

## Quick Start

```bash
docker compose up -d
docker exec -it duckdb duckdb /data/app.duckdb
```

That's it. No `.env` to copy, no explicit `build` step — [docker-compose.yml](docker-compose.yml) has sensible defaults baked in and `up -d` auto-builds the image on first run.

Inside the shell you'll land on a `D ` prompt:

```sql
SELECT version();
SELECT schema_name FROM information_schema.schemata
 WHERE schema_name IN ('bronze','silver','gold');
.quit
```

The `.duckdb` file now lives at [`./data/app.duckdb`](data/) on the host — ready to be opened by Python, dbt-duckdb, or any other local tool.

## How it works

What happens when you run `docker compose up -d`:

1. Compose builds `duckdb-local:1.2.2` from the local [Dockerfile](Dockerfile) — a single DuckDB CLI binary on `debian:bookworm-slim`, no extra services.
2. The container starts with `sh -c "duckdb /data/app.duckdb < /init.sql && exec tail -f /dev/null"`.
3. That one-liner does two things:
   - Runs [`init.sql`](init.sql) against `/data/app.duckdb`, which creates `bronze`/`silver`/`gold` schemas if they don't exist. `init.sql` is idempotent, so it runs harmlessly on every start.
   - After init completes, `exec tail -f /dev/null` replaces the shell with `tail`, keeping the container alive as PID 1 with a cleanly-handled signal loop. Nothing holds a connection to the `.duckdb` file while the container is idle — the file is free for host-side tools to open.
4. You connect by running `docker exec -it duckdb duckdb /data/app.duckdb`. This spawns a *new* DuckDB CLI process inside the existing container, which opens the file and takes a write lock for the duration of your session.

Because the container idles with no open DuckDB connection, **the `.duckdb` file is unlocked by default**. The write lock only appears while you have an interactive session running inside the container (or run a `-c` one-off). This matters for [concurrent access from the host](#concurrent-access-caveat).

## Using DuckDB — hello world

A complete "drop a file, query it, persist it" walk-through. Run these on your host.

**1.** Make some sample data:

```bash
cat > data/orders.csv <<'CSV'
order_id,customer,amount,created_at
1,alice,19.99,2026-04-01
2,bob,49.50,2026-04-01
3,alice,12.00,2026-04-02
4,charlie,99.00,2026-04-02
5,alice,7.25,2026-04-03
CSV
```

**2.** Open the SQL shell:

```bash
docker exec -it duckdb duckdb /data/app.duckdb
```

**3.** Query the CSV in place — no load step required:

```sql
SELECT * FROM read_csv('/data/orders.csv', header = true);
SELECT customer, count(*), sum(amount)
  FROM read_csv('/data/orders.csv', header = true)
 GROUP BY customer;
```

**4.** Persist into `bronze`:

```sql
CREATE OR REPLACE TABLE bronze.orders AS
SELECT * FROM read_csv('/data/orders.csv', header = true);

SELECT count(*) FROM bronze.orders;
```

**5.** Transform into `silver` with real types + basic cleaning:

```sql
CREATE OR REPLACE TABLE silver.orders AS
SELECT order_id::BIGINT         AS order_id,
       lower(customer)          AS customer,
       amount::DECIMAL(10,2)    AS amount,
       created_at::DATE         AS created_at
  FROM bronze.orders
 WHERE order_id IS NOT NULL;
```

**6.** Aggregate into `gold`:

```sql
CREATE OR REPLACE TABLE gold.daily_revenue AS
SELECT created_at AS day,
       count(*)   AS n_orders,
       sum(amount) AS revenue
  FROM silver.orders
 GROUP BY ALL
 ORDER BY day;

SELECT * FROM gold.daily_revenue;
```

**7.** Export the gold table back to Parquet on the host:

```sql
COPY gold.daily_revenue TO '/data/daily_revenue.parquet' (FORMAT PARQUET);
```

**8.** Exit:

```sql
.quit
```

The file `data/daily_revenue.parquet` is now on your host, readable by any Parquet-aware tool. `data/app.duckdb` holds all three schemas with the tables you just created — it survives `docker compose down` and reappears on the next `up -d`.

### Useful DuckDB shell commands

| Command | Purpose |
|---|---|
| `.help` | list all dot-commands |
| `.tables` | list tables in the current connection |
| `.schema bronze` | show DDL for everything in `bronze` |
| `.mode csv` / `.mode markdown` | change result output format |
| `.maxwidth 0` | stop truncating wide columns |
| `.timer on` | show query wall-time after each query |
| `.read /data/some.sql` | execute a SQL file |
| `.quit` | exit |

### Running a one-off query (no interactive shell)

```bash
docker exec duckdb duckdb /data/app.duckdb \
  -c "SELECT count(*) FROM gold.daily_revenue;"
```

Or pipe a whole SQL file in from the host:

```bash
docker exec -i duckdb duckdb /data/app.duckdb < queries/my_report.sql
```

## Operations

Everyday commands, all run from inside this template directory:

| Action | Command |
|---|---|
| **Start** (builds image on first run) | `docker compose up -d` |
| **Open a SQL shell** | `docker exec -it duckdb duckdb /data/app.duckdb` |
| **Run one SQL statement** | `docker exec duckdb duckdb /data/app.duckdb -c "SELECT version();"` |
| **Pipe a SQL file in** | `docker exec -i duckdb duckdb /data/app.duckdb < file.sql` |
| **View logs** | `docker compose logs -f duckdb` |
| **Restart** (re-runs `init.sql`) | `docker compose restart` |
| **Stop** (keeps data) | `docker compose stop` |
| **Remove container** (keeps data — it's on the bind mount) | `docker compose down` |
| **Full wipe** | `docker compose down && rm -rf data/*` |
| **Rebuild after bumping `DUCKDB_VERSION`** | `docker compose build && docker compose up -d` |

## Using it as a DWH

The workflow is **land → bronze → silver → gold**, all driven by SQL against a single file.

**Land** files by dropping them into `./data/` on the host. They appear at `/data/...` inside the container instantly — no copy, no upload.

```bash
cp ~/Downloads/events.parquet duckdb/data/
```

**Ingest into bronze** by reading the files in place:

```sql
CREATE OR REPLACE TABLE bronze.events AS
SELECT * FROM read_parquet('/data/events.parquet');

CREATE OR REPLACE TABLE bronze.orders AS
SELECT * FROM read_csv('/data/orders.csv', header = true);
```

**Clean into silver:**

```sql
CREATE OR REPLACE TABLE silver.events AS
SELECT id,
       lower(event_type)              AS event_type,
       try_cast(payload AS JSON)      AS payload,
       cast(ingested_at AS TIMESTAMP) AS ingested_at
  FROM bronze.events
 WHERE id IS NOT NULL;
```

**Curate into gold:**

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

Apply per session or add them to [`init.sql`](init.sql) if you want them baked in.

## Connecting from the host

The `.duckdb` file is a regular file on your host. Any local tool can open it — as long as nothing else holds a write lock.

### Python

```bash
pip install duckdb
```

```python
import duckdb
con = duckdb.connect("data/app.duckdb", read_only=True)
print(con.sql("SELECT * FROM gold.daily_revenue").df())
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

### Concurrent-access caveat

DuckDB allows **one writer OR many readers** per file, not both at the same time. This template's container idles with *no* open connection (it just runs `tail -f /dev/null`), so the file is unlocked by default and host-side readers work without ceremony.

The write lock appears only when you have an interactive session inside the container (`docker exec -it duckdb duckdb ...`) or an in-flight `-c` one-off. If a host-side tool gets `IO Error: Could not set lock on file`, either:

- open the host-side connection with `read_only=True`,
- close the container-side session first, or
- `docker compose stop` if you need an exclusive host writer.

## Configuration

All variables have defaults in [docker-compose.yml](docker-compose.yml); you only need a `.env` file if you want to override them. Copy the example:

```bash
cp .env.example .env
```

| Variable | Description | Default |
|----------|-------------|---------|
| `DUCKDB_VERSION` | CLI version baked into the image (build arg) | `1.2.2` |
| `DUCKDB_DB` | Database filename inside `./data/` | `app.duckdb` |

Changing `DUCKDB_VERSION` requires `docker compose build && docker compose up -d` to rebuild the image. Changing `DUCKDB_DB` just creates a different file on next start — `init.sql` is idempotent and will re-apply the schemas to it.

## Backups

DuckDB is a single file. The simplest backup is a copy — but release any write lock first:

```bash
docker compose stop
cp data/app.duckdb data/app.duckdb.$(date +%F)
docker compose start
```

For a version-portable backup that survives DuckDB storage-format upgrades, use `EXPORT DATABASE` — it writes schema SQL + Parquet files for every table:

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
- **Prometheus metrics / alternative logging driver** — plug in whatever you already run (`loki`, `fluentd`, `syslog`) via the `logging.driver` field.

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

**`IO Error: Could not set lock on file`** — another DuckDB process has the file open for writing. Close the other session, or open the new one with `read_only=True`.

**`./data/` is owned by root after first boot** — the container runs as root and writes through the bind mount. Fix ownership once with `sudo chown -R $USER:$USER data/`, or just run host-side commands via `docker exec` instead so they inherit root's permissions.

**Init didn't pick up my edit to `init.sql`** — it runs every start, but the statements use `IF NOT EXISTS`, so re-runs won't *recreate* existing objects. For destructive changes, drop them manually first, then restart.

**`docker compose up -d` says "variable is not set"** — you have an older copy of this compose file without the `${VAR:-default}` fallbacks. Pull the latest, or `cp .env.example .env`.
