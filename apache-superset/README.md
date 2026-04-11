# Apache Superset

Modern, open-source business intelligence web app — SQL exploration, interactive charts, and dashboards on top of any SQL warehouse.

This is a **production-ready single-host stack**: Superset web (gunicorn) + Celery worker + Celery beat + Postgres (metadata) + Redis (cache, results backend, Celery broker). The Superset config and init/bootstrap script are embedded inline in [docker-compose.yml](docker-compose.yml) via Compose `configs:`, so the whole template is four files.

## Services

| Service | Port | Role |
|---------|------|------|
| `superset` | 8088 | Web UI + REST API (gunicorn) |
| `superset-worker` | — | Celery worker: async SQL Lab, alerts, reports, thumbnails, cache warmup |
| `superset-worker-beat` | — | Celery beat scheduler — enqueues periodic tasks (alerts, cache) |
| `superset-init` | — | One-shot: `db upgrade` → create admin → `superset init` |
| `postgres` | — | Superset's **metadata** database (dashboards, charts, users, permissions) |
| `redis` | — | DB 0: Celery broker · DB 1: async query results · DB 2: data cache |

`postgres` here stores Superset's own metadata — it is **not** the data you visualize. Point Superset at your warehouses (ClickHouse, Postgres, MySQL, DuckDB, …) from inside the UI under **Settings → Database Connections**.

## Quick start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. Generate a real secret key and paste it into `.env` as `SUPERSET_SECRET_KEY`:

```bash
openssl rand -base64 42
```

3. Start the stack:

```bash
docker compose up -d
```

The `superset-init` service runs once (schema migration + admin user + roles), then `superset`, `superset-worker`, and `superset-worker-beat` come up. First boot takes ~60 s.

4. Open [http://localhost:8088](http://localhost:8088) and log in with the admin credentials from `.env` (default: `admin` / `admin`).

## Configuration

All settings live in [.env](.env.example). The inline `superset_config.py` inside [docker-compose.yml](docker-compose.yml) reads them at container start.

| Variable | Description | Default |
|---|---|---|
| `SUPERSET_IMAGE` | Superset Docker image (pin a version) | `apache/superset:4.1.1` |
| `SUPERSET_PORT` | Host port for the web UI | `8088` |
| `SUPERSET_SECRET_KEY` | **Required.** Signs sessions + encrypts stored DB passwords | `CHANGE_ME...` |
| `SUPERSET_ADMIN_USERNAME` | Admin login created on first init | `admin` |
| `SUPERSET_ADMIN_PASSWORD` | Admin password created on first init | `admin` |
| `SUPERSET_ADMIN_EMAIL` | Admin email address | `admin@superset.local` |
| `POSTGRES_DB` / `_USER` / `_PASSWORD` | Metadata DB credentials | `superset` / `superset` / `superset` |
| `CELERY_WORKER_CONCURRENCY` | Celery worker process count | `4` |
| `SUPERSET_LOAD_EXAMPLES` | Load Superset's example dashboards on first init | `no` |
| `ADDITIONAL_PIP_PACKAGES` | Extra SQLAlchemy drivers installed at container start | *(empty)* |

> **`SUPERSET_SECRET_KEY` is load-bearing.** It signs user session cookies and encrypts every database password stored in the metadata DB. **Rotating it after databases have been saved will break those connections** — Superset won't be able to decrypt the old passwords. Pick a real value *before* the first `docker compose up -d` and keep it.
>
> **Admin credentials are set on first init only.** After that, change passwords from the UI (**Settings → List Users**) or with `superset fab reset-password`.

### Adding database drivers (no image rebuild)

The stock `apache/superset:4.x` image ships with very few drivers — not even `psycopg2`, which the metadata Postgres needs. The bootstrap script therefore **always** installs `psycopg2-binary` at container start (hardcoded in the inline `superset_bootstrap` config inside [docker-compose.yml](docker-compose.yml)).

For any other warehouse, list the pip packages in `ADDITIONAL_PIP_PACKAGES` in `.env` — the bootstrap script installs them at container start on every service (web, worker, beat, init):

```bash
ADDITIONAL_PIP_PACKAGES=clickhouse-connect==0.8.6 duckdb-engine==0.13.2 pymssql==2.3.0 trino==0.330.0
```

Then recreate the containers:

```bash
docker compose up -d --force-recreate
```

Drivers for the other templates in this repo:

| Warehouse | Pip package | SQLAlchemy URI |
|---|---|---|
| PostgreSQL | `psycopg2-binary` *(auto-installed)* | `postgresql+psycopg2://user:pass@host:5432/db` |
| MySQL | `mysqlclient` or `pymysql` | `mysql://user:pass@host:3306/db` |
| Apache Doris | `pymysql` *(MySQL-compatible)* | `mysql+pymysql://user:pass@host:9030/db` |
| Microsoft SQL Server | `pymssql` | `mssql+pymssql://user:pass@host:1433/db` |
| ClickHouse | `clickhouse-connect` | `clickhousedb://user:pass@host:8123/db` |
| DuckDB | `duckdb-engine` | `duckdb:////path/to/file.duckdb` |

For a permanent, reproducible setup (CI, prod images, air-gapped hosts) prefer a real `Dockerfile` with `RUN pip install -r requirements.txt` — the `ADDITIONAL_PIP_PACKAGES` path trades reproducibility for a simpler template.

### Connecting to another template's database

All the database templates in this repo default to `127.0.0.1` on the host. To reach them from inside the Superset containers, use:

- **On Linux** — add `extra_hosts: ["host.docker.internal:host-gateway"]` to the Superset services (or use the host's LAN IP).
- **Same Compose project** — put the stacks on a shared external network.

Example: connect to the [ClickHouse](../clickhouse/) template running on the host at `127.0.0.1:8123`:

```
clickhousedb://default:clickhouse@host.docker.internal:8123/default
```

## What Celery is doing in this stack

Celery is Superset's task queue — it runs work *off* the web request path so gunicorn isn't blocked by long jobs. Four use cases:

1. **Async SQL Lab queries.** When a query is marked "Run Async" (or exceeds `SUPERSET_WEBSERVER_TIMEOUT`), the web server hands it to Celery. The worker executes it against the upstream database, stores the rows in Redis (`RESULTS_BACKEND`), and the browser polls for them.
2. **Alerts & Reports.** Scheduled email/Slack alerts and scheduled dashboard deliveries (PDF/PNG). `celery beat` enqueues them on cron (`beat_schedule` in the inline config), `celery worker` executes them via a headless browser screenshot.
3. **Thumbnails.** Dashboard and chart preview images rendered in the background.
4. **Cache warmup.** Periodic jobs that pre-populate the Redis data cache so dashboards load instantly.

Three moving parts:

| Component | Container | Redis DB | Notes |
|---|---|---|---|
| Broker | *(Redis)* | 0 | Queue of pending tasks. Web app pushes, workers pull. |
| Worker | `superset-worker` | — | Runs tasks. Scale out by raising `CELERY_WORKER_CONCURRENCY` or running multiple worker containers. |
| Beat | `superset-worker-beat` | — | Cron-like scheduler. **Run exactly one replica.** Two beats = duplicate task firings. |
| Results | *(Redis)* | 1 | Where async SQL Lab query results are cached until the browser picks them up. |
| Cache | *(Redis)* | 2 | Data cache / filter state / explore form cache. |

To verify Celery is healthy:

```bash
# worker ping
docker exec superset-worker celery --app=superset.tasks.celery_app:app inspect ping

# inspect the Redis broker
docker exec superset-redis redis-cli -n 0 llen celery
```

## Data persistence

| Volume | Mount | Contains |
|---|---|---|
| `postgres-data` | `/var/lib/postgresql/data` | Superset metadata DB (dashboards, charts, users, saved queries) |
| `redis-data` | `/data` | Redis AOF/RDB — cache, results, Celery state (safe to lose) |
| `superset-home` | `/app/superset_home` | SQLite fallback dir, upload staging, generated thumbnails, logs |

```bash
# Stop (keeps all data)
docker compose down

# Stop and wipe everything — loses dashboards, charts, users
docker compose down -v
```

### Backups

The only volume you need to back up is `postgres-data` (or rather, its contents):

```bash
# Logical dump
docker exec -t superset-postgres \
  pg_dump -U superset -d superset -F c -f /tmp/superset.dump
docker cp superset-postgres:/tmp/superset.dump ./superset.dump

# Restore into a fresh stack
docker cp ./superset.dump superset-postgres:/tmp/superset.dump
docker exec -it superset-postgres \
  pg_restore -U superset -d superset --clean --if-exists /tmp/superset.dump
```

You can also export/import individual dashboards from the UI as ZIP bundles — useful for moving a single dashboard between environments.

## Common operations

### Create or reset a user

```bash
# Add a new admin
docker exec -it superset superset fab create-admin \
  --username jane --firstname Jane --lastname Doe \
  --email jane@example.com --password 'changeme'

# Reset a password
docker exec -it superset superset fab reset-password \
  --username admin --password 'newpassword'
```

### Apply metadata schema upgrades after bumping `SUPERSET_IMAGE`

```bash
docker compose pull
docker compose up -d
# superset-init re-runs `superset db upgrade` automatically on each start
```

### Tail logs

```bash
docker compose logs -f superset           # web
docker compose logs -f superset-worker    # Celery worker
docker compose logs -f superset-worker-beat
```

### Scale Celery workers

Either raise concurrency inside the existing worker container:

```bash
# Edit .env → CELERY_WORKER_CONCURRENCY=8, then:
docker compose up -d --force-recreate superset-worker
```

Or run multiple worker containers:

```bash
docker compose up -d --scale superset-worker=3
```

> Do **not** scale `superset-worker-beat` — there must be exactly one beat process or scheduled reports will fire multiple times per interval.

## Troubleshooting

### Init container fails with `FATAL: password authentication failed`

`POSTGRES_PASSWORD` only takes effect on an empty `postgres-data` volume. If you changed it after first boot, either wipe the volume (`docker compose down -v`) or update the password from inside Postgres:

```bash
docker exec -it superset-postgres psql -U superset -c "ALTER USER superset WITH PASSWORD 'newpass'"
```

### "The CSRF session token is missing" / sessions keep logging out

Usually `SUPERSET_SECRET_KEY` is empty or was rotated while users had live sessions. Set a stable value and restart: `docker compose restart superset superset-worker superset-worker-beat`.

### Saved database connection stops working after rotating `SUPERSET_SECRET_KEY`

Database passwords stored in the metadata DB are encrypted with the old key — the new key can't decrypt them. Either restore the old key, or delete and re-create the database connection from the UI. (Superset ships a `superset re-encrypt-secrets` CLI for planned rotations.)

### SQL Lab "Run Async" does nothing

Async mode requires the worker to be reachable. Check:

```bash
docker compose ps superset-worker
docker exec superset-worker celery --app=superset.tasks.celery_app:app inspect ping
```

If Celery can't reach Redis, the worker will log `ConnectionError: Error 111 connecting to redis:6379` on startup.

### Alerts and scheduled reports never fire

Two things must be true:

1. `superset-worker-beat` is running (check `docker compose ps`).
2. `ALERT_REPORTS` is enabled in the feature flags. It is — see `FEATURE_FLAGS` in the inline config in [docker-compose.yml](docker-compose.yml).

For screenshots to work, Superset also needs a headless browser inside the worker image. The stock `apache/superset` image ships with Chromium; if alerts render blank dashboards, check `docker compose logs superset-worker` for webdriver errors.

### Port 8088 already in use

Change `SUPERSET_PORT` in `.env` and `docker compose up -d`.

## Going further

- [Superset docs — Configuring Superset](https://superset.apache.org/docs/configuration/configuring-superset/)
- [Superset docs — Async Queries via Celery](https://superset.apache.org/docs/configuration/async-queries-celery/)
- [Superset docs — Alerts and Reports](https://superset.apache.org/docs/configuration/alerts-reports/)
- [Superset docs — Feature Flags](https://superset.apache.org/docs/configuration/configuring-superset/#feature-flags)
