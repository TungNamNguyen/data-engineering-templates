# Microsoft SQL Server

Microsoft's flagship relational database — deep T-SQL feature set, first-class tooling (SSMS, Azure Data Studio), and broad BI/ETL support. The Linux container image is published by Microsoft on `mcr.microsoft.com/mssql/server` and is feature-equivalent to the Windows product for most workloads.

This is a **lightweight, single-node** setup with production-ready container settings (memory cap, persistent volume, healthcheck, restart policy) plus a one-shot **init sidecar** that bootstraps an application database and user and runs your `initdb.d/*.sql` scripts — something the upstream image does not provide out of the box.

## Services

| Service | Port | Description |
|---------|------|-------------|
| SQL Server | 1433 | Standard TDS wire protocol — `sqlcmd`, SSMS, JDBC, ODBC, every ORM |
| `mssql-init` | — | One-shot sidecar; creates `MSSQL_DATABASE` / `MSSQL_USER` and runs `initdb.d/*.sql`, then exits |

## Quick Start

1. Copy the environment file:

```bash
cp .env.example .env
```

2. **Pick a strong SA password.** SQL Server refuses to start otherwise — it must be ≥8 characters and contain at least 3 of: uppercase, lowercase, digits, symbols. Edit `.env` and change `MSSQL_SA_PASSWORD` (and `MSSQL_PASSWORD`).

3. Start the server:

```bash
docker compose up -d
```

4. Wait ~30 seconds for the healthcheck to pass and the init sidecar to finish, then connect:

```bash
docker exec -it mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U mssql -P "$MSSQL_PASSWORD" -C -d app
```

> The `-C` flag tells `sqlcmd` to trust the server's self-signed certificate. On SQL Server 2022+ the client enforces encryption by default, so `-C` (or `-N` + a proper cert) is required.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `MSSQL_IMAGE` | Server Docker image | `mcr.microsoft.com/mssql/server:2022-latest` |
| `MSSQL_PID` | Edition — `Developer`, `Express`, `Standard`, `Enterprise`, `EnterpriseCore` | `Developer` |
| `MSSQL_SA_PASSWORD` | Password for the built-in `sa` login (applied on first startup) | `Your_strong_Password123` |
| `MSSQL_DATABASE` | Application database created by the init sidecar | `app` |
| `MSSQL_USER` | Application login/user created by the init sidecar | `mssql` |
| `MSSQL_PASSWORD` | Password for `MSSQL_USER` | `Your_strong_Password123` |
| `MSSQL_PORT` | Host port for the TDS protocol | `1433` |
| `MSSQL_COLLATION` | Server collation applied on first startup only | `SQL_Latin1_General_CP1_CI_AS` |

> **Password policy.** If SQL Server crashes immediately after `docker compose up -d`, check the logs — a weak `MSSQL_SA_PASSWORD` is the most common cause. The container logs will say "the password does not meet SQL Server password policy requirements".

> **Credentials are applied on first startup only.** Once `mssql-data` has been populated, changing `MSSQL_SA_PASSWORD` in `.env` has no effect — you must either `docker compose down -v` to wipe and re-init, or `ALTER LOGIN sa WITH PASSWORD = 'new-password'` from an existing session.

> **ARM64 hosts (Apple Silicon).** The official `mssql/server` images are x86_64 only. On Apple Silicon either enable Rosetta emulation in Docker Desktop, or swap `MSSQL_IMAGE` for `mcr.microsoft.com/azure-sql-edge:latest`, which is ARM-native but missing some surface area (SQL Agent, FileStream, full-text).

### Editions

`MSSQL_PID=Developer` is free and has the full Enterprise feature set, but is **licensed for development and testing only — not for production**. For production use set `MSSQL_PID` to a paid edition or `Express` (free, 10 GB database limit).

### Tuning

Runtime settings are passed as environment variables in [docker-compose.yml](docker-compose.yml). Defaults target a small/medium host (~2 GB of RAM available to SQL Server):

| Setting | Default | Notes |
|---|---|---|
| `MSSQL_MEMORY_LIMIT_MB` | `2048` | Hard cap on server memory. Rule of thumb: 75–80% of container RAM on a dedicated host |
| `MSSQL_AGENT_ENABLED` | `true` | Enables SQL Agent — required for scheduled jobs |
| `MSSQL_TCP_PORT` | `1433` | Internal listener port |
| `MSSQL_COLLATION` | `SQL_Latin1_General_CP1_CI_AS` | Case-insensitive, accent-sensitive — the traditional default |

The full list of supported environment variables is documented at [learn.microsoft.com/sql/linux/sql-server-linux-configure-environment-variables](https://learn.microsoft.com/sql/linux/sql-server-linux-configure-environment-variables).

## Connecting

### `sqlcmd` (inside the container)

```bash
docker exec -it mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U mssql -P "$MSSQL_PASSWORD" -C -d app
```

### `sqlcmd` (from the host)

```bash
sqlcmd -S 127.0.0.1,1433 -U mssql -P "$MSSQL_PASSWORD" -C -d app
```

### JDBC

```
jdbc:sqlserver://127.0.0.1:1433;databaseName=app;encrypt=true;trustServerCertificate=true
```

### Azure Data Studio / SSMS

1. **New Connection**
2. Fill in:
   - **Server:** `127.0.0.1,1433`
   - **Authentication type:** SQL Login
   - **User name:** `mssql`
   - **Password:** value of `MSSQL_PASSWORD` from `.env`
   - **Database:** `app`
   - **Trust server certificate:** ✅ (the container uses a self-signed cert)
3. Click **Connect**

### Python

```python
# pyodbc — needs the Microsoft ODBC Driver 18 installed on the client
import pyodbc
conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=127.0.0.1,1433;DATABASE=app;UID=mssql;PWD=Your_strong_Password123;"
    "Encrypt=yes;TrustServerCertificate=yes;"
)
cur = conn.cursor()
cur.execute("SELECT @@VERSION")
print(cur.fetchone()[0])

# SQLAlchemy
from sqlalchemy import create_engine, text
engine = create_engine(
    "mssql+pyodbc://mssql:Your_strong_Password123@127.0.0.1:1433/app"
    "?driver=ODBC+Driver+18+for+SQL+Server&TrustServerCertificate=yes"
)
with engine.connect() as conn:
    print(conn.execute(text("SELECT @@VERSION")).scalar())
```

## Init scripts (initdb.d/)

Unlike postgres/mysql, the official mssql image has no built-in init mechanism. The `mssql-init` sidecar in [docker-compose.yml](docker-compose.yml) plays that role: it waits for the main server to become healthy, then dispatches every `*.sh` and `*.sql` file in `./initdb.d` in alphabetical order. `.sh` files run under bash (they open their own `sqlcmd` sessions at server scope); `.sql` files run via `sqlcmd -d MSSQL_DATABASE`.

Every template in this repo follows the same three-file layout:

| File | Purpose |
|---|---|
| [`01-infra-setup.sh`](initdb.d/01-infra-setup.sh) | Creates `MSSQL_DATABASE`, the legacy `MSSQL_USER` login (with `db_owner`), and the data-engineering logins (`transform_user`, `read_user`). Also grants `transform_user` the database-scoped `CREATE TABLE / VIEW / PROCEDURE / FUNCTION` rights — see "Permission model" below. |
| [`02-logical-setup.sql`](initdb.d/02-logical-setup.sql) | Creates the `bronze`, `silver`, `gold` schemas inside `MSSQL_DATABASE`, owned by `transform_user`. Uses `EXEC('CREATE SCHEMA …')` because T-SQL requires `CREATE SCHEMA` to be the first statement in a batch. |
| [`03-governance.sql`](initdb.d/03-governance.sql) | Grants `read_user` SELECT on each schema. `transform_user` already owns the schemas, so no explicit grant is needed. `GRANT SELECT ON SCHEMA::` covers existing **and** future tables — no default-privileges mechanism required. |

### Accounts and layers

| Account | Privileges | Notes |
|---|---|---|
| `sa` | Superuser | From `MSSQL_SA_PASSWORD` |
| `${MSSQL_USER}` (default `mssql`) | `db_owner` on `${MSSQL_DATABASE}` | Legacy app user — kept for backwards compatibility |
| `transform_user` | Owner of `bronze`, `silver`, `gold` schemas | Full control (DDL + DML) on all three layers |
| `read_user` | `SELECT` on `bronze`, `silver`, `gold` schemas | Read-only; covers existing + future tables |

The medallion layers (**bronze** raw, **silver** cleaned, **gold** curated) live as *schemas* inside `${MSSQL_DATABASE}` — SQL Server has a real schema layer, just like Postgres.

Set `TRANSFORM_USER_PASSWORD` and `READ_USER_PASSWORD` in `.env` before the first `docker compose up -d`. Avoid single quotes in the values.

### Permission model

SQL Server splits create permissions by scope: schema ownership (via `AUTHORIZATION` in `02-logical-setup.sql`) controls **where** objects land, but the `CREATE TABLE / VIEW / PROCEDURE / FUNCTION` grants in `01-infra-setup.sh` are what actually let `transform_user` create them. Owning a schema is necessary but not sufficient — both pieces are required. This is different from Postgres, where schema ownership alone implies full DDL.

> **Write idempotent SQL.** Unlike postgres/mysql — which only run init scripts against an empty data directory — the `mssql-init` sidecar runs every time you `docker compose up -d`. Use `IF NOT EXISTS` / `IF ... IS NULL` guards so re-runs are no-ops. The included scripts already do.

### When init scripts run

**MSSQL is the outlier** — the other templates in this repo use the server's built-in entrypoint, which runs `initdb.d/` only once against an empty data directory. The mssql image has no such mechanism, so we run a sidecar (`mssql-init`) that executes every time the stack comes up. That means **editing a script and running `docker compose up -d` *does* re-apply the change** — provided the script is idempotent (the bundled ones are).

| Action | Data volume | Scripts run? |
|---|---|---|
| First `docker compose up -d` | empty | **yes** |
| `docker compose restart` | populated | no (sidecar is not restarted by `restart`) |
| `docker compose down` then `up -d` | populated | **yes** — sidecar runs again; idempotent guards matter |
| `docker compose down -v` then `up -d` | wiped → empty | **yes** |
| Editing a file in `initdb.d/`, then `up -d` | populated | **yes** — the new content is applied on the next `up` |

Treat `initdb.d/` as **bootstrap, not migrations**. The every-up-d re-run is a convenience for iterating on the bootstrap itself, not a substitute for a real migration tool (Flyway, DbUp, Liquibase, EF Core Migrations) once the project is live.

To re-run the sidecar on-demand without restarting the main server:

```bash
docker compose up -d --force-recreate mssql-init
```

To apply a single script by hand (e.g. just the grants) without touching the sidecar:

```bash
# Re-apply the grants (idempotent — safe to re-run)
docker exec -i mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -d app \
    < initdb.d/03-governance.sql
```

If you edit `01-infra-setup.sh` and want the changes reflected without re-running the full sidecar, read it, adapt the inline T-SQL, and execute it as `sa` — the `.sh` file itself isn't something you can pipe through `sqlcmd`.

## Data persistence

| Volume | Mount | Contains |
|--------|-------|----------|
| `mssql-data` | `/var/opt/mssql` | System and user databases, transaction logs, error logs — **the database** |

```bash
# Stop containers (keeps data)
docker compose down

# Stop and wipe everything
docker compose down -v
```

### Backups

Native `.bak` backup (portable across SQL Server installs):

```bash
docker exec -t mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C \
    -Q "BACKUP DATABASE [app] TO DISK = N'/var/opt/mssql/backup/app.bak' WITH INIT, COMPRESSION, CHECKSUM;"
```

> Create the backup directory first: `docker exec -t mssql mkdir -p /var/opt/mssql/backup`. It lives inside the `mssql-data` volume so it survives restarts.

Restore:

```bash
docker exec -t mssql /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C \
    -Q "RESTORE DATABASE [app] FROM DISK = N'/var/opt/mssql/backup/app.bak' WITH REPLACE;"
```

### Point-in-time recovery

PITR requires the `FULL` recovery model plus regular log backups. Freshly created databases inherit the recovery model from `model`, which is `SIMPLE` in the Linux container image. Switch explicitly:

```sql
ALTER DATABASE [app] SET RECOVERY FULL;
BACKUP DATABASE [app] TO DISK = N'/var/opt/mssql/backup/app_full.bak' WITH INIT;
BACKUP LOG      [app] TO DISK = N'/var/opt/mssql/backup/app_log.trn' WITH INIT;
```

## Common operations

### Server status

```sql
SELECT @@VERSION;
SELECT name, state_desc, recovery_model_desc FROM sys.databases;
SELECT DB_NAME(database_id) AS db,
       SUM(size) * 8 / 1024 AS size_mb
FROM sys.master_files
GROUP BY database_id;
EXEC sp_who2;
```

### Create a table

```sql
CREATE TABLE dbo.users (
    id          BIGINT IDENTITY(1,1) NOT NULL,
    email       NVARCHAR(255)        NOT NULL,
    created_at  DATETIME2(6)         NOT NULL CONSTRAINT DF_users_created_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_users PRIMARY KEY CLUSTERED (id),
    CONSTRAINT UQ_users_email UNIQUE (email)
);
```

### Top expensive queries (from the plan cache)

```sql
SELECT TOP 20
    qs.execution_count,
    qs.total_worker_time / 1000            AS total_cpu_ms,
    qs.total_elapsed_time / 1000           AS total_elapsed_ms,
    qs.total_logical_reads                 AS total_reads,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
              ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text)
                    ELSE qs.statement_end_offset END - qs.statement_start_offset) / 2) + 1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY qs.total_worker_time DESC;
```

### Buffer pool hit ratio

```sql
SELECT
    (CAST((SELECT cntr_value FROM sys.dm_os_performance_counters
           WHERE counter_name = 'Buffer cache hit ratio'       AND object_name LIKE '%Buffer Manager%') AS FLOAT)
   / NULLIF((SELECT cntr_value FROM sys.dm_os_performance_counters
             WHERE counter_name = 'Buffer cache hit ratio base' AND object_name LIKE '%Buffer Manager%'), 0)) * 100
    AS hit_ratio_pct;
```

Aim for above `99%` on read-heavy workloads.

### Create a read-only user

```sql
USE [app];
CREATE LOGIN [reader] WITH PASSWORD = N'Reader_Password123', CHECK_POLICY = OFF;
CREATE USER  [reader] FOR LOGIN [reader];
EXEC sp_addrolemember N'db_datareader', N'reader';
```

## Troubleshooting

### Container exits immediately with "password does not meet SQL Server password policy"

`MSSQL_SA_PASSWORD` must be ≥8 characters and contain at least 3 of: uppercase, lowercase, digits, symbols. Edit `.env`, then `docker compose down -v && docker compose up -d` (the volume must be wiped because the failed startup left it in an inconsistent state).

### `Login failed for user 'sa'` after changing `.env`

`MSSQL_SA_PASSWORD` only takes effect on a fresh data volume. If you changed it afterwards, either wipe the volume (`down -v`) or connect with the old password and run:

```sql
ALTER LOGIN sa WITH PASSWORD = N'new-password';
```

### `sqlcmd: Error: Microsoft ODBC Driver 18 for SQL Server: SSL Provider`

This is the 2022+ client refusing to talk to a server without a trusted TLS cert. Add `-C` (trust server certificate) to your `sqlcmd` invocation, or provision a real certificate.

### Init sidecar never finishes / keeps restarting

Check its logs:

```bash
docker compose logs mssql-init
```

Common causes: the main server isn't healthy yet (the sidecar waits for the healthcheck — give it 30–60 s on first run), or a SQL script in `initdb.d/` errors out. The sidecar uses `sqlcmd -b`, so any error aborts and the exit code is non-zero.

### Running on Apple Silicon / ARM64

The `mcr.microsoft.com/mssql/server` images are x86_64 only. Switch to `mcr.microsoft.com/azure-sql-edge:latest` in `.env` for an ARM-native build (missing SQL Agent and a few other features), or enable Rosetta emulation in Docker Desktop.

### Container is healthy but the app can't connect

Make sure your driver is trusting the self-signed cert (`TrustServerCertificate=yes` / `-C` / `trustServerCertificate=true` depending on the client). On 2022+ the server ships with encryption enforced.

### View server logs

```bash
docker compose logs mssql | tail -100
docker compose logs -f mssql
```

SQL Server's own ERRORLOG lives inside the container at `/var/opt/mssql/log/errorlog`:

```bash
docker exec -it mssql tail -f /var/opt/mssql/log/errorlog
```
