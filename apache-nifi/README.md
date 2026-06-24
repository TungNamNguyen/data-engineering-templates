# Apache NiFi

A drag-and-drop tool for moving and transforming data between systems in real time. You build a *flow* on a visual canvas — boxes (processors) connected by queues — and NiFi handles the routing, buffering, retries, and back-pressure for you. Every piece of data is tracked end to end, so you can always see where a record came from and what happened to it.

This is a **secured, single-node** setup with production-ready container settings (HTTPS + login, persistent repositories, tuned heap, healthchecks, restart policy) plus **NiFi Registry** for putting your flows under version control. The [Clustering](#clustering-production) section covers scaling to a multi-node HA cluster.

## Services

| Service | Port | Description |
|---------|------|-------------|
| NiFi | 8443 | Dataflow engine + web UI, over **HTTPS** with single-user login |
| NiFi Registry | 18080 | Version control for flows — commit, promote dev→prod, roll back |

## NiFi components (what's what)

Things you build with, on the canvas:

| Component | What it is |
|---|---|
| **FlowFile** | The unit of data moving through NiFi. It has two parts: **content** (the actual bytes — a CSV row, a JSON doc, a file) and **attributes** (key/value metadata, e.g. `filename`, `mime.type`). |
| **Processor** | A box that does *one* thing to FlowFiles: fetch, transform, route, or send. Examples: `GetFile`, `ConvertRecord`, `PutDatabaseRecord`, `PublishKafka`. You wire processors together to form a flow. |
| **Connection / Queue** | The link between two processors. FlowFiles wait here in a queue. If the downstream is slow, the queue fills and applies **back-pressure** — NiFi pauses the upstream automatically so nothing is lost. |
| **Process Group** | A folder that groups a set of processors into one reusable, version-controllable unit (the thing you commit to Registry). |
| **Controller Service** | Shared, reusable config used by many processors — e.g. a **DBCPConnectionPool** (a database connection) or a schema registry. This is where your JDBC driver gets referenced. |
| **Funnel / Port** | Helpers to merge many connections into one, or to send/receive data between process groups (and between NiFi instances via site-to-site). |

Behind the scenes, NiFi keeps state in four **repositories** — these are exactly the volumes this template persists:

| Repository | Role |
|---|---|
| **FlowFile repository** | The "what's in flight right now" ledger — each FlowFile's attributes and which queue it sits in. Write-ahead log, so a crash doesn't lose in-progress data. |
| **Content repository** | The actual bytes of every FlowFile's content. The biggest/most disk-hungry one. |
| **Provenance repository** | The audit trail / lineage — every event (created, modified, routed, sent) for every FlowFile, so you can replay "where did this record come from?". |
| **Database repository** | A small internal H2 DB for things like component status history. |

And two pieces outside the engine:

- **NiFi Registry** — a separate service that stores *versions* of your process groups. Connect NiFi to it once, then you can commit changes, see diffs, roll back, and import the same flow into another NiFi instance.
- **The flow definition (`flow.json.gz`)** — your entire canvas, serialized to a file inside the `conf` volume. This is why persisting `conf` = persisting your flows.

## Quick Start

1. Copy the environment file and set strong values:

```bash
cp .env.example .env
```

Edit `.env` and set, at minimum:

- `NIFI_PASSWORD` — **at least 12 characters** (shorter passwords are silently ignored)
- `NIFI_SENSITIVE_PROPS_KEY` — at least 12 characters; generate with `openssl rand -base64 24`

2. Start the stack:

```bash
docker compose up -d
```

3. NiFi takes ~1–2 minutes to come up (it generates a self-signed cert and builds its repositories on first boot). Watch until healthy:

```bash
docker compose ps          # wait for STATUS "healthy"
docker compose logs -f nifi
```

4. Open the UI at **https://localhost:8443/nifi**. Your browser will warn about the self-signed certificate — that's expected; accept it and continue. Log in with `NIFI_USERNAME` / `NIFI_PASSWORD` from `.env`.

> **HTTPS only.** NiFi 2.x does not serve plain HTTP. Use `https://`, not `http://`, and include `/nifi` in the path.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `NIFI_IMAGE` | NiFi Docker image | `apache/nifi:2.10.0` |
| `NIFI_REGISTRY_IMAGE` | NiFi Registry image (lags the core line) | `apache/nifi-registry:2.8.0` |
| `NIFI_USERNAME` | Web UI login name | `admin` |
| `NIFI_PASSWORD` | Web UI password (**≥ 12 chars**) | `change-me-at-least-12-chars` |
| `NIFI_SENSITIVE_PROPS_KEY` | Encryption key for sensitive properties (**≥ 12 chars**) | `change-me-at-least-12-chars` |
| `NIFI_WEB_PROXY_HOST` | Host:port(s) allowed in the Host header | `localhost:8443` |
| `NIFI_JVM_HEAP_INIT` | Initial JVM heap | `2g` |
| `NIFI_JVM_HEAP_MAX` | Maximum JVM heap | `2g` |
| `NIFI_HTTPS_PORT` | Host port for the NiFi UI | `8443` |
| `NIFI_REGISTRY_PORT` | Host port for the Registry UI | `18080` |

> **The password is only read on first startup.** It is baked into `login-identity-providers.xml` inside the `nifi-conf` volume the first time NiFi boots. Changing `NIFI_PASSWORD` afterwards has no effect until you wipe that volume (`docker compose down -v`) or update the file by hand.

> **Guard `NIFI_SENSITIVE_PROPS_KEY` like a secret.** It encrypts every password/token stored inside your processors. If you lose it, those properties can't be decrypted and the flow won't start; if it differs between two instances, you can't import flows between them. Set it once, keep it stable, and store it somewhere safe.

> **"System Error / request blocked".** This means the Host header you used isn't in `NIFI_WEB_PROXY_HOST`. Add the host:port you're browsing with (or your reverse-proxy name) to that variable, comma-separated, and recreate the container.

## Putting flows under version control

NiFi Registry is what makes flows reproducible and promotable instead of living only on one canvas. Connect NiFi to it once:

1. In the NiFi UI, open the hamburger menu (top-right) → **Controller Settings** → **Registry Clients** → **+**.
2. Name it `local-registry` and set the URL to **`http://nifi-registry:18080`** (use the service name — NiFi reaches Registry over the internal docker network, not via `localhost`).
3. Open the Registry UI at http://localhost:18080/nifi-registry and create a **bucket** (e.g. `dev`).
4. Back in NiFi, right-click a process group → **Version → Start version control**, pick the bucket, and commit.

From then on you can commit changes, see diffs, revert to any previous version, and import the same flow into another NiFi instance pointed at the same Registry.

> The Registry runs **unsecured (HTTP)** here, which is fine for an internal docker network. For a production deployment exposed beyond the host, secure it with TLS/LDAP (set `AUTH=tls` or `AUTH=ldap` and mount keystores) or keep it on a private network behind NiFi.

## Adding JDBC drivers (connecting to a database)

NiFi does **not** ship JDBC drivers, so to read from / write to a database you supply the driver `.jar` yourself. The `drivers/` directory is bind-mounted into the container at `/opt/nifi/drivers`, so you just drop the jar there — no image rebuild.

### 1. Download the driver into `drivers/`

Pick the one matching your database:

```bash
# PostgreSQL
curl -L -o drivers/postgresql-42.7.4.jar \
  https://jdbc.postgresql.org/download/postgresql-42.7.4.jar

# MySQL
curl -L -o drivers/mysql-connector-j-9.1.0.jar \
  https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/9.1.0/mysql-connector-j-9.1.0.jar

# SQL Server
curl -L -o drivers/mssql-jdbc-12.8.1.jre11.jar \
  https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/12.8.1.jre11/mssql-jdbc-12.8.1.jre11.jar
```

### 2. Make the jar visible to the container

```bash
docker compose restart nifi
```

The file now lives inside the container at `/opt/nifi/drivers/<your-driver>.jar`.

### 3. Create a DBCPConnectionPool controller service

In the NiFi UI: open a process group → right-click the canvas → **Controller Services** → **+** → add **DBCPConnectionPool**, then fill in:

| Property | PostgreSQL example | MySQL example |
|---|---|---|
| Database Connection URL | `jdbc:postgresql://<host>:5432/<db>` | `jdbc:mysql://<host>:3306/<db>` |
| Database Driver Class Name | `org.postgresql.Driver` | `com.mysql.cj.jdbc.Driver` |
| **Database Driver Location(s)** | `/opt/nifi/drivers/postgresql-42.7.4.jar` | `/opt/nifi/drivers/mysql-connector-j-9.1.0.jar` |
| Database User | your DB user | your DB user |
| Password | your DB password | your DB password |

Click the lightning bolt to **enable** the service. Processors like `PutDatabaseRecord`, `ExecuteSQL`, or `QueryDatabaseTable` can now select this controller service.

> **`<host>` is not `localhost`.** From inside the NiFi container, `localhost` means NiFi itself. Use the database container's service name (if it's on the same docker network), or the host machine's IP — not `localhost`.

> The password you enter is encrypted at rest with `NIFI_SENSITIVE_PROPS_KEY`, which is why that key must stay stable (see the warning under [Configuration](#configuration)).

### Adding whole NiFi extensions (NARs)

For custom or third-party NiFi extensions (packaged as `.nar`), mount them to the autoload directory — add a line under the `nifi` service `volumes:` and they load without a restart:

```yaml
- ./extensions:/opt/nifi/nifi-current/extensions
```

## Data persistence

State is split across named volumes so each piece can be backed up or cleared independently:

| Volume | Mount | Contains |
|--------|-------|----------|
| `nifi-conf` | `…/conf` | **Your flow** (`flow.json.gz`), `nifi.properties`, login + keystore files |
| `nifi-state` | `…/state` | Component state (e.g. last-read positions of source processors) |
| `nifi-flowfile` | `…/flowfile_repository` | Metadata + attributes of data currently in the flow |
| `nifi-content` | `…/content_repository` | The actual bytes of in-flight data |
| `nifi-provenance` | `…/provenance_repository` | Lineage / audit trail of every event |
| `nifi-database` | `…/database_repository` | Internal H2 DB (component history, etc.) |
| `nifi-logs` | `…/logs` | `nifi-app.log`, `nifi-user.log`, `nifi-bootstrap.log` |
| `registry-database` | `…/database` | Registry's bucket + flow metadata |
| `registry-flow-storage` | `…/flow_storage` | Committed flow versions (snapshots) |

```bash
# Stop containers (keeps all data)
docker compose down

# Stop and wipe everything (flows, history, credentials — all gone)
docker compose down -v
```

> `down -v` deletes your flows. Commit anything you care about to NiFi Registry first, or back up the `nifi-conf` volume.

## Clustering (production)

A single secured node is durable and survives restarts, but a **cluster** adds high availability and horizontal throughput. NiFi nodes coordinate through Apache ZooKeeper and each node runs an identical copy of the flow.

To turn this template into a node of a cluster, add an external ZooKeeper and set the clustering variables on the `nifi` service:

```yaml
  zookeeper:
    image: bitnami/zookeeper:3.9
    container_name: zookeeper
    environment:
      ALLOW_ANONYMOUS_LOGIN: "yes"
    volumes:
      - zookeeper-data:/bitnami/zookeeper
    restart: unless-stopped

  nifi:
    environment:
      # ... existing variables ...
      NIFI_CLUSTER_IS_NODE: "true"
      NIFI_CLUSTER_ADDRESS: nifi          # this node's reachable hostname
      NIFI_CLUSTER_NODE_PROTOCOL_PORT: "8082"
      NIFI_ZK_CONNECT_STRING: "zookeeper:2181"
      NIFI_ELECTION_MAX_WAIT: "1 min"
      NIFI_ELECTION_MAX_CANDIDATES: "3"    # number of nodes to wait for
```

Then run one container per node, each with a unique `NIFI_CLUSTER_ADDRESS`/hostname, all pointing at the same ZooKeeper. Notes for a real deployment:

- **Secure node-to-node traffic.** A cluster needs mutual TLS between nodes — generate a keystore/truststore (the [NiFi Toolkit](https://hub.docker.com/r/apache/nifi-toolkit) `tls-toolkit` does this) and provide them via `KEYSTORE_*` / `TRUSTSTORE_*` env vars and `AUTH=tls`.
- **Run 3 ZooKeeper nodes** (not one) so the coordinator survives a single failure.
- **Use per-node repository volumes** — never share content/flowfile repositories between nodes.
- Put a load balancer in front of the nodes for the UI and for site-to-site ingestion.

## Common operations

### Service status and logs

```bash
docker compose ps
docker compose logs -f nifi
docker compose logs -f nifi-registry

# Tail NiFi's application log directly
docker compose exec nifi tail -100 /opt/nifi/nifi-current/logs/nifi-app.log
```

### Recover a forgotten / auto-generated password

If `NIFI_PASSWORD` was under 12 characters, NiFi generated random credentials on first boot:

```bash
docker compose logs nifi | grep -i "Generated"
```

To reset to a known value, set a 12+ char `NIFI_PASSWORD` in `.env` and re-init the login provider:

```bash
docker compose exec nifi ./bin/nifi.sh set-single-user-credentials "$NIFI_USERNAME" "$NIFI_PASSWORD"
docker compose restart nifi
```

### Shell into a container

```bash
docker compose exec nifi bash
```

### Upgrading NiFi

1. Commit your flows to NiFi Registry (your safety net).
2. Bump `NIFI_IMAGE` in `.env` to the new tag.
3. `docker compose pull nifi && docker compose up -d nifi`

The `nifi-conf` volume carries `flow.json.gz` forward, so the flow is preserved across the upgrade. Stay on the 2.x line — moving from 1.x to 2.x is a migration, not an in-place upgrade.

## Troubleshooting

### UI won't load / `ERR_SSL_PROTOCOL_ERROR`

You're using `http://`. NiFi 2.x is HTTPS-only — browse to `https://localhost:8443/nifi` and accept the self-signed certificate warning.

### "The request contained an invalid host header" / request blocked

The host:port in your browser isn't listed in `NIFI_WEB_PROXY_HOST`. Add it (comma-separated) in `.env` and recreate: `docker compose up -d --force-recreate nifi`.

### Login fails with the password from `.env`

The password is only applied on the **first** boot. If you changed it afterwards, either reset it with `set-single-user-credentials` (see above) or wipe and re-init: `docker compose down -v && docker compose up -d` (this deletes all flows — commit them first).

### Container is "unhealthy" or keeps restarting

```bash
docker compose logs nifi | tail -80
```

Common causes:
- **Not enough memory** — NiFi needs heap (`NIFI_JVM_HEAP_MAX`) *plus* off-heap room for repositories. Give Docker at least 4 GB, or lower the heap.
- **Bad sensitive-props key** — if you changed `NIFI_SENSITIVE_PROPS_KEY` against an existing `nifi-conf` volume, NiFi can't decrypt the flow. Look for `Sensitive Properties Key` errors in the log.
- **Still booting** — first start can take 1–2 minutes; the healthcheck allows 120s before it counts failures.

### NiFi can't connect to the Registry

Use the **service name** as the host: `http://nifi-registry:18080`, not `http://localhost:18080`. Inside the docker network, `localhost` is the NiFi container itself.

### Out of disk space

The content and provenance repositories grow with throughput. NiFi ages them off automatically, but you can tighten retention via `nifi.content.repository.archive.max.retention.period` and `nifi.provenance.repository.max.storage.*` in `conf/nifi.properties`. To reclaim Docker space generally:

```bash
docker system prune -f
```
