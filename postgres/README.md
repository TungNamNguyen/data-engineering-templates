# PostgreSQL

Open-source relational database with strong SQL support, ACID transactions, and a rich extension ecosystem (PostGIS, pgvector, TimescaleDB, etc.).

This is a **lightweight, single-node** setup with production-ready container settings (tuned `postgresql.conf` via command flags, persistent volume, healthcheck, restart policy).

## Services

| Service | Port | Description |
|---------|------|-------------|
| PostgreSQL | 5432 | Standard Postgres wire protocol — `psql`, JDBC, libpq, every ORM |

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
docker exec -it postgres psql -U postgres -d app
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_IMAGE` | Server Docker image | `postgres:16-alpine` |
| `POSTGRES_DB` | Database created on first startup | `app` |
| `POSTGRES_USER` | Superuser created on first startup | `postgres` |
| `POSTGRES_PASSWORD` | Superuser password applied on first startup | `postgres` |
| `POSTGRES_PORT` | Host port for the Postgres protocol | `5432` |

> **Credentials are set on first startup only.** If you change `POSTGRES_PASSWORD` after the data volume exists, the new value is ignored. Either `docker compose down -v` to wipe and re-init, or change it from inside a session with `ALTER USER postgres WITH PASSWORD 'new-password'`.

### Tuning `postgresql.conf`

Runtime settings are passed as `-c key=value` flags in [docker-compose.yml](docker-compose.yml). Defaults target a small/medium host (≈2 GB RAM available to Postgres):

| Setting | Default | Notes |
|---|---|---|
| `max_connections` | `200` | Use a pooler (PgBouncer) before raising this |
| `shared_buffers` | `256MB` | Rule of thumb: 25% of RAM |
| `effective_cache_size` | `1GB` | Rule of thumb: 50–75% of RAM |
| `work_mem` | `16MB` | Per sort/hash op, per connection — multiply carefully |
| `maintenance_work_mem` | `128MB` | Used by `VACUUM`, `CREATE INDEX`, `ALTER TABLE` |
| `wal_level` | `replica` | Required for streaming replication and `pg_basebackup` |
| `max_wal_size` | `2GB` | Raise for write-heavy workloads to spread checkpoints |
| `checkpoint_completion_target` | `0.9` | Smooths checkpoint I/O |
| `random_page_cost` | `1.1` | Assumes SSD storage |
| `log_min_duration_statement` | `500` | Log queries slower than 500 ms |

For a proper sizing pass, feed your host specs into [PGTune](https://pgtune.leopard.in.ua/) and update the flags.

## Connecting

### psql (inside the container)

```bash
docker exec -it postgres psql -U postgres -d app
```

### psql (from the host)

```bash
psql "postgres://postgres:postgres@localhost:5432/app"
```

### JDBC

```
jdbc:postgresql://127.0.0.1:5432/app
```

### DBeaver

1. **New Database Connection** > select **PostgreSQL**
2. Fill in:
   - **Host:** `127.0.0.1`
   - **Port:** `5432`
   - **Database:** `app`
   - **Username:** `postgres`
   - **Password:** value of `POSTGRES_PASSWORD` from `.env`
3. Click **Test Connection**, then **Finish**

### Python

```python
# psycopg 3 (recommended)
import psycopg
with psycopg.connect("postgres://postgres:postgres@localhost:5432/app") as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT version()")
        print(cur.fetchone())

# SQLAlchemy
from sqlalchemy import create_engine, text
engine = create_engine("postgresql+psycopg://postgres:postgres@localhost:5432/app")
with engine.connect() as conn:
    print(conn.execute(text("SELECT version()")).scalar())
```

## Init scripts (initdb.d/)

The `initdb.d/` folder is mounted at `/docker-entrypoint-initdb.d/` in the container. On **first startup only** — when the data directory is empty — the entrypoint runs every `*.sql`, `*.sql.gz`, and `*.sh` in alphabetical order against the `POSTGRES_DB`.

The included [`initdb.d/01_create_schema.sql`](initdb.d/01_create_schema.sql) creates an `example` schema with a sample `events` table and useful indexes (including a GIN index on JSONB).

Add your own scripts with a numbered prefix to control order:

```
initdb.d/
├── 01_create_schema.sql     # included
├── 02_create_roles.sql      # your own
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

Treat `initdb.d/` as **bootstrap, not migrations**. For ongoing schema changes, use a real migration tool (Flyway, Liquibase, Alembic, golang-migrate, dbmate).

To apply a script change without wiping data:

```bash
docker exec -i postgres psql -U postgres -d app < initdb.d/01_create_schema.sql
```

## Data persistence

| Volume | Mount | Contains |
|--------|-------|----------|
| `postgres-data` | `/var/lib/postgresql/data` | Heap, WAL, system catalogs, config — **the database** |

`PGDATA` is set to `/var/lib/postgresql/data/pgdata` so the cluster lives in a subdirectory of the mount point — this avoids the occasional `lost+found` / permissions issue when mounting a bind directory straight onto `PGDATA`.

```bash
# Stop containers (keeps data)
docker compose down

# Stop and wipe everything
docker compose down -v
```

### Backups

Logical dump (portable, slow for large DBs):

```bash
docker exec -t postgres pg_dump -U postgres -d app -F c -f /tmp/app.dump
docker cp postgres:/tmp/app.dump ./app.dump
```

Restore:

```bash
docker cp ./app.dump postgres:/tmp/app.dump
docker exec -it postgres pg_restore -U postgres -d app --clean --if-exists /tmp/app.dump
```

Physical base backup (fast, suitable for PITR with WAL archiving):

```bash
docker exec -t postgres pg_basebackup -U postgres -D /tmp/basebackup -Ft -z -P
```

## Common operations

### Server status

```sql
SELECT version();
SELECT pg_size_pretty(pg_database_size('app'));
SELECT * FROM pg_stat_activity WHERE state != 'idle';
```

### Create a table

```sql
CREATE SCHEMA my_app;

CREATE TABLE my_app.users (
    id          BIGSERIAL PRIMARY KEY,
    email       TEXT UNIQUE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Top slow queries (requires `pg_stat_statements`)

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT
    round(total_exec_time::numeric, 2) AS total_ms,
    calls,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

> `pg_stat_statements` also needs `shared_preload_libraries = 'pg_stat_statements'`. Add `-c shared_preload_libraries=pg_stat_statements` to the `command:` block in [docker-compose.yml](docker-compose.yml) and recreate the container.

### Cache hit ratio

```sql
SELECT
    sum(heap_blks_read)                                   AS disk_reads,
    sum(heap_blks_hit)                                    AS cache_hits,
    round(sum(heap_blks_hit)::numeric
          / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0), 4) AS hit_ratio
FROM pg_statio_user_tables;
```

Aim for a hit ratio above `0.99` on read-heavy workloads.

## Troubleshooting

### Authentication failed / password doesn't work

`POSTGRES_PASSWORD` only takes effect on an empty data volume. If you changed it afterwards, either wipe the volume (`down -v`) or run `ALTER USER postgres WITH PASSWORD 'new-password'` from an existing session.

### Init script didn't run

Init scripts only run on a **fresh** `postgres-data` volume. Run `docker compose down -v` then `up -d` to re-init, or apply the SQL manually.

### `FATAL: sorry, too many clients already`

You've hit `max_connections`. Either raise it in the `command:` block (costs memory per connection), or — the correct fix — put a pooler like PgBouncer in front.

### View server logs

```bash
docker compose logs postgres | tail -100
docker compose logs -f postgres
```
