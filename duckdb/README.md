# DuckDB

Fast in-process analytical database — columnar, vectorized, zero-config. Think "SQLite for analytics". This template packages it as a **lightweight file-based data warehouse**: the upstream official [`duckdb/duckdb`](https://hub.docker.com/r/duckdb/duckdb) image for both CLI sessions and schema initialization, plus a single `.duckdb` file on disk you can open from anything. **No custom image, no Dockerfile, no build step** — just `docker compose up -d`.

DuckDB is not a server. There is no daemon to keep running between queries — each CLI invocation opens the file, runs, and exits. The container model reflects that: nothing idles, sessions are spawned on demand with `docker compose run --rm`.

## Layout

```
duckdb/
├── docker-compose.yml       # main service + init sidecar (both official image)
├── initdb.d/
│   ├── 01-infra-setup.sql   # near-no-op — DuckDB has no env-injected infra
│   ├── 02-logical-setup.sql # CREATE SCHEMA bronze / silver / gold
│   └── 03-governance.sql    # documented no-op (DuckDB has no users/grants)
├── .env.example             # optional overrides: DUCKDB_VERSION, DUCKDB_DB
└── data/                    # bind mount — .duckdb file + landing files
```

This template follows the same `initdb.d/` three-file convention as every other database template in this repo. Both [`01-infra-setup.sql`](initdb.d/01-infra-setup.sql) and [`03-governance.sql`](initdb.d/03-governance.sql) are documented near-no-ops because DuckDB has no multi-database concept, no user/role/grant system, and creates the `.duckdb` file implicitly on first open. The middle file ([`02-logical-setup.sql`](initdb.d/02-logical-setup.sql)) is the only one doing real work. Keeping all three files makes the layout uniform so a reader jumping between templates always knows where to look.

## Quick Start

```bash
docker compose up -d                              # pulls the image, runs init
docker compose run --rm duckdb /data/app.duckdb   # opens the SQL shell
```

That's it. No `.env` to copy, no build step — [docker-compose.yml](docker-compose.yml) has sensible defaults baked in, and the upstream image is pulled from Docker Hub on first run.

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

1. Compose pulls the upstream `duckdb/duckdb:1.4.0` image from Docker Hub (on first run only). This is a distroless image containing only the `/duckdb` binary — no shell, no coreutils — so init has to be driven by the CLI itself rather than a bash dispatcher.
2. The `duckdb-init` container starts. Its command is a fixed chain of `-c ".read ..."` flags, one per file in [`initdb.d/`](initdb.d/):
   ```
   /duckdb /data/app.duckdb \
     -c ".read /initdb.d/01-infra-setup.sql" \
     -c ".read /initdb.d/02-logical-setup.sql" \
     -c ".read /initdb.d/03-governance.sql"
   ```
   Opening `/data/app.duckdb` creates the file if it does not exist. DuckDB executes each `.read` in the given order inside a single process, then exits.
3. On this repo's layout that means:
   - [`01-infra-setup.sql`](initdb.d/01-infra-setup.sql) — near-no-op (`SELECT 1;`), exists for convention uniformity.
   - [`02-logical-setup.sql`](initdb.d/02-logical-setup.sql) — `CREATE SCHEMA IF NOT EXISTS bronze / silver / gold`.
   - [`03-governance.sql`](initdb.d/03-governance.sql) — no-op (DuckDB has no grants).
4. `duckdb-init` exits with status 0. Because `restart: "no"`, it stays in the exited state and does not respawn.
5. The main `duckdb` service is under `profiles: ["cli"]` and is **not** started by `up -d`. You run it explicitly when you want a shell:

   ```bash
   docker compose run --rm duckdb /data/app.duckdb
   ```

   This spawns a fresh container from `duckdb/duckdb:1.4.0`, opens the file, takes the DuckDB write lock for the duration of your session, and releases it when you exit. Compose checks `duckdb-init` completed successfully before starting the session.

Because no container holds the file when you aren't actively in a session, the `.duckdb` file is **unlocked by default** — host-side tools (Python, dbt, notebooks) can open it directly. The write lock only appears while you have a `docker compose run` session in flight. See [Concurrent-access caveat](#concurrent-access-caveat) below.

### Adding a new init file

Because the distroless upstream image has no shell, the init sidecar cannot walk `initdb.d/` with a loop — each file is dispatched explicitly from the compose `command:` array. If you add, say, `initdb.d/04-seed-data.sql`, you must also add a matching line to `duckdb-init.command` in [docker-compose.yml](docker-compose.yml):

```yaml
    command:
      - /data/${DUCKDB_DB:-app.duckdb}
      - -c
      - .read /initdb.d/01-infra-setup.sql
      - -c
      - .read /initdb.d/02-logical-setup.sql
      - -c
      - .read /initdb.d/03-governance.sql
      - -c
      - .read /initdb.d/04-seed-data.sql   # new
```

That is the trade-off for running with zero custom images.

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
docker compose run --rm duckdb /data/app.duckdb
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
docker compose run --rm duckdb /data/app.duckdb \
  -c "SELECT count(*) FROM gold.daily_revenue;"
```

Or pipe a whole SQL file in from the host:

```bash
docker compose run --rm -T duckdb /data/app.duckdb < queries/my_report.sql
```

## When init scripts run

The `duckdb-init` sidecar dispatches [`initdb.d/`](initdb.d/) on **every** `docker compose up -d`. All scripts are idempotent by design (`CREATE ... IF NOT EXISTS`, `SELECT 1` on file open), so re-runs are free.

| Situation | What happens |
|---|---|
| **First `up -d`** on an empty `./data/` | `01-infra-setup.sh` creates `/data/${DUCKDB_DB}`, `02-logical-setup.sql` creates the three schemas, `03-governance.sql` is a no-op. |
| **Subsequent `up -d`** on existing data | All three files re-run; every statement is a no-op because the file, schemas, and (absent) grants already exist. |
| **`docker compose down` + `up -d`** | Same as above — `./data/` is a host bind mount, not a named volume, so nothing is wiped. |
| **Full wipe**: `docker compose down && rm -rf data/*` | Next `up -d` bootstraps from scratch. |
| **You edited a file in `initdb.d/`** | The change is picked up on the next `up -d`. If your edit is destructive (e.g. `DROP SCHEMA`), the idempotent guard won't save you — that is by design. |
| **You want to re-run init manually** without restarting everything | `docker compose run --rm duckdb-init` re-dispatches the full pipeline. |

## Operations

Everyday commands, all run from inside this template directory:

| Action | Command |
|---|---|
| **Start** (pulls image on first run, applies initdb.d) | `docker compose up -d` |
| **Open a SQL shell** | `docker compose run --rm duckdb /data/app.duckdb` |
| **Run one SQL statement** | `docker compose run --rm duckdb /data/app.duckdb -c "SELECT version();"` |
| **Pipe a SQL file in** | `docker compose run --rm -T duckdb /data/app.duckdb < file.sql` |
| **Re-apply init scripts** | `docker compose run --rm duckdb-init` |
| **View init logs** | `docker compose logs duckdb-init` |
| **Stop** (no-op — nothing is running) | `docker compose down` |
| **Full wipe** | `docker compose down && rm -rf data/*` |
| **Upgrade DuckDB** | Edit `DUCKDB_VERSION` in `.env`, then `docker compose pull && docker compose up -d` |

## Using it as a DWH

The workflow is **land → bronze → silver → gold**, all driven by SQL against a single file.

**Land** files by dropping them into `./data/` on the host. They appear at `/data/...` inside any session container instantly — no copy, no upload.

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

Apply per session, or add them to [`02-logical-setup.sql`](initdb.d/02-logical-setup.sql) if you want them baked in on every `up -d`.

## Connecting from the host

The `.duckdb` file is a regular file on your host. Any local tool can open it — as long as no `docker compose run` session holds a write lock.

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

DuckDB allows **one writer OR many readers** per file, not both at the same time. This template's default state is *no container running*, so the file is unlocked by default and host-side readers work without ceremony.

The write lock appears only while a `docker compose run --rm duckdb ...` session is in flight. If a host-side tool gets `IO Error: Could not set lock on file`, either:

- open the host-side connection with `read_only=True`,
- exit the `docker compose run` session first, or
- make sure no other process (dbt, Python, another terminal) has an exclusive handle.

## Configuration

All variables have defaults in [docker-compose.yml](docker-compose.yml); you only need a `.env` file if you want to override them. Copy the example:

```bash
cp .env.example .env
```

| Variable | Description | Default |
|----------|-------------|---------|
| `DUCKDB_VERSION` | Official image tag used by both the main service and the init sidecar | `1.4.0` |
| `DUCKDB_DB` | Database filename inside `./data/` | `app.duckdb` |

Changing `DUCKDB_VERSION` just changes the image tag both services resolve to — run `docker compose pull && docker compose up -d` and the new tag is used immediately. Changing `DUCKDB_DB` creates a different file on next `up -d`; the init SQL is idempotent and will re-apply the schemas to it.

## Backups

DuckDB is a single file. The simplest backup is a copy — but make sure no session is holding the write lock:

```bash
cp data/app.duckdb data/app.duckdb.$(date +%F)
```

For a version-portable backup that survives DuckDB storage-format upgrades, use `EXPORT DATABASE` — it writes schema SQL + Parquet files for every table:

```bash
docker compose run --rm duckdb /data/app.duckdb \
    -c "EXPORT DATABASE '/data/backup-$(date +%F)' (FORMAT PARQUET);"
```

Round-trip with `IMPORT DATABASE '/data/backup-YYYY-MM-DD';`.

## Production notes

Both services ship with defense-in-depth defaults that are free (one-liners, no runtime cost):

| Setting | Applies to | Why |
|---|---|---|
| `init: true` | both | Runs tini as PID 1 so signals forward cleanly and zombies get reaped. |
| `security_opt: [no-new-privileges:true]` | both | Blocks privilege escalation via setuid binaries. |
| `profiles: ["cli"]` on `duckdb` | main | Prevents `up -d` from starting a container with no long-running command. Sessions are spawned on demand. |
| `restart: "no"` on `duckdb-init` | init | One-shot — runs once per `up -d` and exits. |
| `depends_on: service_completed_successfully` | main | Sessions won't start until init has finished. |
| `logging.max-size: 10m` + `max-file: 3` | init | Caps stdout at 30 MB so a chatty init script can't fill host disk. |
| Pinned `DUCKDB_VERSION` on both services | both | Both containers resolve to the same upstream tag — no version skew between init and sessions. |

Deliberately not included (add these in a `docker-compose.override.yml` when you actually need them):

- **Resource limits (`deploy.resources`)** — host-specific. For a small host:
    ```yaml
    deploy:
      resources:
        limits:
          cpus: "4"
          memory: 8G
    ```
- **Non-root user** — would require UID/GID juggling against the bind mount; not worthwhile on a single-tenant dev workload.
- **Healthcheck** — there is no daemon to probe.

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

**`IO Error: Could not set lock on file`** — another DuckDB process has the file open for writing. Exit any in-flight `docker compose run` session, or open the new one with `read_only=True`.

**`./data/` is owned by root after first boot** — both containers run as root and write through the bind mount. Fix ownership once with `sudo chown -R $USER:$USER data/`.

**Init didn't pick up my edit to `initdb.d/`** — it runs every `up -d`, but the statements are idempotent (`CREATE ... IF NOT EXISTS`), so re-runs won't *recreate* existing objects. For destructive changes, drop the object manually first, then re-run `docker compose run --rm duckdb-init`.

**`docker compose up -d` just finishes with no running container** — that is correct. Only `duckdb-init` runs on `up -d`, and it exits as soon as init is done. `docker compose ps -a` will show it in the `exited (0)` state. `docker compose run --rm duckdb ...` is how you interact with the database.
