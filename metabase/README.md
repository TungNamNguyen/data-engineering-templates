# Metabase

Open-source BI tool for asking questions about your data — point it at a SQL warehouse and build dashboards without writing code.

This is a **production-ready single-host stack**: Metabase web (Jetty) + Postgres for Metabase's application database. Two services, three files — no custom image build required.

## Services

| Service | Port | Role |
|---------|------|------|
| `metabase` | 3000 | Web UI + REST API (Jetty, embedded Java) |
| `postgres` | — | Metabase's **application** database (questions, dashboards, users, permissions) |

`postgres` here stores Metabase's own metadata — it is **not** the data you visualize. Point Metabase at your warehouses (ClickHouse, Postgres, MySQL, BigQuery, …) from inside the UI under **Admin settings → Databases**.

> Metabase defaults to an embedded H2 file database if you don't configure `MB_DB_TYPE`. **H2 is not safe for production** (no concurrent access, no backups, can corrupt on crash). This template wires up Postgres as the app DB from the start.

## Quick start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. Generate a real encryption key and paste it into `.env` as `MB_ENCRYPTION_SECRET_KEY`:

```bash
openssl rand -base64 32
```

3. Start the stack:

```bash
docker compose up -d
```

First boot takes ~60–90 s — Metabase runs its Liquibase migrations against the empty Postgres app DB before opening the web port.

4. Open [http://localhost:3000](http://localhost:3000) and complete the **setup wizard**. The first account you create becomes the admin. Unlike Superset, Metabase has no env-var shortcut for creating the initial admin — the wizard is the only path.

## Configuration

All settings live in [.env](.env.example). Metabase reads its own `MB_*` variables directly from the environment; this compose file also uses `POSTGRES_*` to wire the app DB to Postgres.

| Variable | Description | Default |
|---|---|---|
| `METABASE_IMAGE` | Metabase Docker image (pin a version) | `metabase/metabase:v0.52.4` |
| `METABASE_PORT` | Host port for the web UI | `3000` |
| `MB_SITE_URL` | Public URL — used for email links, embeds, public sharing | `http://localhost:3000` |
| `MB_SITE_NAME` | Display name shown in the UI and emails | `Metabase` |
| `MB_ENCRYPTION_SECRET_KEY` | **Required for prod.** Encrypts saved database passwords in the app DB | `CHANGE_ME...` |
| `POSTGRES_DB` / `_USER` / `_PASSWORD` | App DB credentials | `metabase` / `metabase` / `metabase` |
| `JAVA_OPTS` | JVM flags (mainly heap size) | `-Xmx2g` |
| `MB_TIMEZONE` | JVM timezone — affects scheduled pulses and timestamps | `UTC` |
| `MB_PASSWORD_COMPLEXITY` | User password policy: `weak` \| `normal` \| `strong` | `normal` |

> **`MB_ENCRYPTION_SECRET_KEY` is load-bearing.** It encrypts every database connection password Metabase stores in the app DB. **Rotating it after databases have been saved will make those connections unreadable** — Metabase won't be able to decrypt the old passwords. Pick a real value *before* the first `docker compose up -d` and keep it.

### Connecting to another template's database

All the database templates in this repo default to `127.0.0.1` on the host. To reach them from inside the Metabase container:

- **On Linux** — add `extra_hosts: ["host.docker.internal:host-gateway"]` to the `metabase` service (or use the host's LAN IP).
- **Same Compose project** — put the stacks on a shared external network.

Example: connect to the [PostgreSQL](../postgres/) template running on the host at `127.0.0.1:5432` — in the Metabase UI under **Admin → Databases → Add database**, choose *PostgreSQL* and use host `host.docker.internal`.

## Data persistence

| Volume | Mount | Contains |
|---|---|---|
| `postgres-data` | `/var/lib/postgresql/data` | Metabase app DB (questions, dashboards, users, collections, permissions) |
| `metabase-data` | `/metabase-data` | Plugins, GeoJSON uploads, logs, any leftover H2 files |

```bash
# Stop (keeps all data)
docker compose down

# Stop and wipe everything — loses questions, dashboards, users
docker compose down -v
```

### Backups

The only volume you *need* to back up is `postgres-data`:

```bash
# Logical dump
docker exec -t metabase-postgres \
  pg_dump -U metabase -d metabase -F c -f /tmp/metabase.dump
docker cp metabase-postgres:/tmp/metabase.dump ./metabase.dump

# Restore into a fresh stack
docker cp ./metabase.dump metabase-postgres:/tmp/metabase.dump
docker exec -it metabase-postgres \
  pg_restore -U metabase -d metabase --clean --if-exists /tmp/metabase.dump
```

You can also serialize collections to YAML with `docker exec metabase java -jar /app/metabase.jar export /metabase-data/export` — useful for moving dashboards between environments without a full DB restore.

## Common operations

### Upgrade Metabase

```bash
# Edit .env → bump METABASE_IMAGE, then:
docker compose pull
docker compose up -d
# Metabase runs Liquibase migrations against the app DB on startup.
```

Metabase upgrades are one-way — **back up `postgres-data` before upgrading**. Major versions cannot be rolled back.

### Tail logs

```bash
docker compose logs -f metabase
```

### Reset an admin password (lost access)

```bash
# Generates a temporary reset token — paste it into the URL Metabase prints.
docker exec -it metabase java -jar /app/metabase.jar reset-password admin@example.com
```

### Run Metabase CLI commands

```bash
# List all CLI subcommands
docker exec -it metabase java -jar /app/metabase.jar help
```

## Troubleshooting

### Metabase stays unhealthy for the first minute

Normal — the JVM plus Liquibase migrations take 60–90 seconds on a cold boot. The compose healthcheck has `start_period: 90s`. If it's still unhealthy after ~3 minutes, check `docker compose logs metabase`.

### `FATAL: password authentication failed for user "metabase"`

`POSTGRES_PASSWORD` only takes effect on an empty `postgres-data` volume. If you changed it after first boot, either wipe the volume (`docker compose down -v`) or update the password from inside Postgres:

```bash
docker exec -it metabase-postgres \
  psql -U metabase -c "ALTER USER metabase WITH PASSWORD 'newpass'"
```

### Saved database connection stops working after rotating `MB_ENCRYPTION_SECRET_KEY`

Database passwords stored in the app DB are encrypted with the old key — the new key can't decrypt them. Either restore the old key, or delete and re-create the affected database connections from the UI.

### "OutOfMemoryError: Java heap space"

The default `-Xmx2g` is enough for small-to-medium instances. Large dashboards or heavy CSV exports may need more:

```bash
# In .env
JAVA_OPTS=-Xmx4g
```

Then `docker compose up -d --force-recreate metabase`.

### Port 3000 already in use

Change `METABASE_PORT` in `.env` and `docker compose up -d`.

## Going further

- [Metabase docs — Running Metabase on Docker](https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker)
- [Metabase docs — Configuring the application database](https://www.metabase.com/docs/latest/installation-and-operation/configuring-application-database)
- [Metabase docs — Encrypting your database connection](https://www.metabase.com/docs/latest/installation-and-operation/encrypting-database-details-at-rest)
- [Metabase docs — Environment variables](https://www.metabase.com/docs/latest/configuring-metabase/environment-variables)
- [Metabase docs — Serialization (export/import)](https://www.metabase.com/docs/latest/installation-and-operation/serialization)
