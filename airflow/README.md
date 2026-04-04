# Airflow Docker Compose Template

Production-ready Apache Airflow 3.1.8 template using CeleryExecutor with PostgreSQL and Redis.

## Prerequisites

- Docker and Docker Compose installed
- At least 4GB of RAM allocated to Docker
- At least 2 CPUs

## Project Structure

```
airflow/
├── docker-compose.yml      # All Airflow services
├── Dockerfile              # Custom image (base + your pip packages)
├── .env                    # Your local credentials (gitignored)
├── .env.example            # Template for .env (safe to commit)
├── .gitignore              # Ignores logs, .env, __pycache__
├── .dockerignore           # Keeps Docker build context small
├── requirements.txt        # Your Python dependencies
├── dags/                   # DAG definitions (scheduling logic only)
│   └── example_dag.py
├── src/                    # Business logic (Python package)
│   ├── __init__.py
│   └── etl/
│       ├── __init__.py
│       └── extract.py
├── plugins/                # Custom Airflow plugins (hooks, operators, sensors)
├── config/                 # Airflow config overrides (e.g. airflow.cfg)
├── tests/                  # Your tests
└── logs/                   # Auto-created, gitignored
```

## Services

| Service | Description | Port |
|---------|-------------|------|
| **airflow-apiserver** | Web UI + REST API | `localhost:8080` |
| **airflow-scheduler** | Schedules DAG runs | - |
| **airflow-dag-processor** | Parses DAG files | - |
| **airflow-worker** | Executes tasks (Celery) | - |
| **airflow-triggerer** | Handles deferrable operators | - |
| **postgres** | Metadata database | 5432 |
| **redis** | Celery message broker | 6379 |
| **flower** (opt-in) | Celery monitoring UI | `localhost:5555` |

## Getting Started

### 1. Configure environment variables

```bash
cp .env.example .env
```

Edit `.env` and set your credentials. For production, generate a Fernet key:

```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

### 2. Build and start

```bash
docker compose build
docker compose up -d
```

This will automatically initialize the database, create the admin user, and start all services.

### 3. Fix directory permissions (Linux only)

After the first start, some directories will be owned by the Airflow container user. Fix this so you can edit files locally:

```bash
sudo chown -R $(whoami):$(whoami) dags/ src/ plugins/ logs/ config/
```

### 4. Access the UI

Open http://localhost:8080 and log in with the credentials from your `.env` file (default: `airflow` / `airflow`).

## How to Use

### Adding Python dependencies

1. Add packages to `requirements.txt`
2. Rebuild: `docker compose build && docker compose up -d`

### Writing DAGs and scripts

DAGs in `dags/` should be thin — just scheduling and task definitions. Put your actual logic in `src/`.

`PYTHONPATH` is set to `/opt/airflow/src`, so DAGs can import directly:

```python
# dags/my_dag.py
from etl.extract import fetch_data     # imports from src/etl/extract.py
```

When adding new directories under `src/`, always include an `__init__.py` file (can be empty) to make them importable as Python packages. For example:

```
src/
├── __init__.py          # required
└── my_new_module/
    ├── __init__.py      # required
    └── transform.py
```

### Using plugins

Place custom Airflow hooks, operators, or sensors in `plugins/`. Files here are automatically loaded by Airflow at startup.

### Using config overrides

The `config/` directory is mounted at `/opt/airflow/config` inside the containers. If you need to override default Airflow settings, place an `airflow.cfg` file there. Most projects don't need this — environment variables in `docker-compose.yml` (prefixed with `AIRFLOW__`) are the preferred way to configure Airflow.

### Monitoring Celery workers (optional)

```bash
docker compose --profile flower up -d
```

Then open http://localhost:5555.

## Common Commands

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Stop and remove all data (volumes)
docker compose down -v

# View logs
docker compose logs -f airflow-apiserver
docker compose logs -f airflow-worker

# Check health
curl http://localhost:8080/api/v2/monitor/health

# Trigger a DAG
docker compose exec airflow-apiserver airflow dags trigger <dag_id>

# Enter a container shell
docker compose exec airflow-apiserver bash

# Rebuild after changing requirements.txt
docker compose build && docker compose up -d
```

## Customization

### Changing passwords

Edit your `.env` file with the new credentials:

```bash
POSTGRES_PASSWORD=your_new_db_password
AIRFLOW_WWW_USER=admin
AIRFLOW_WWW_PASSWORD=your_new_ui_password
```

Then recreate everything from scratch:

```bash
docker compose down -v
docker compose up -d
```

The `-v` flag is required — it removes the old database volume so the new credentials take effect.

### Switching to LocalExecutor

If you don't need distributed workers (simpler setup, fewer containers), switch to LocalExecutor:

1. In `docker-compose.yml`, change the executor environment variable:

```yaml
AIRFLOW__CORE__EXECUTOR: LocalExecutor
```

2. Remove or comment out these services (they are only needed for CeleryExecutor):
   - `redis`
   - `airflow-worker`
   - `flower`

3. Remove `redis` from the `depends_on` sections.

4. Remove the `AIRFLOW__CELERY__*` environment variables.

With LocalExecutor, the scheduler runs tasks directly — no workers or Redis needed. Good for development and small-scale deployments.

### Scaling Celery workers

To add more workers for parallel task execution:

```bash
docker compose up -d --scale airflow-worker=3
```

This starts 3 worker containers. Each picks up tasks from the Redis queue independently.

To go back to a single worker:

```bash
docker compose up -d --scale airflow-worker=1
```

### Adding Airflow provider packages

Operators for external services (GCP, AWS, Snowflake, etc.) come from provider packages. Add them to `requirements.txt`:

```
apache-airflow-providers-google==12.0.0
apache-airflow-providers-amazon==9.0.0
```

Then rebuild: `docker compose build && docker compose up -d`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AIRFLOW_UID` | Linux user ID for file permissions | `50000` |
| `AIRFLOW_PROJ_DIR` | Project directory path for volume mounts | `.` |
| `POSTGRES_USER` | PostgreSQL username | `airflow` |
| `POSTGRES_PASSWORD` | PostgreSQL password | `airflow` |
| `POSTGRES_DB` | PostgreSQL database name | `airflow` |
| `REDIS_PASSWORD` | Redis password | (empty) |
| `AIRFLOW_WWW_USER` | Web UI admin username | `airflow` |
| `AIRFLOW_WWW_PASSWORD` | Web UI admin password | `airflow` |
| `AIRFLOW_FERNET_KEY` | Encryption key for connections/variables | (empty) |
| `AIRFLOW_JWT_SECRET` | JWT secret for API authentication | `airflow_jwt_secret` |
| `AIRFLOW_JWT_ISSUER` | JWT issuer for API authentication | `airflow` |

## Troubleshooting

### Permission denied when editing dags/ or src/

The `airflow-init` container runs as root and changes ownership of mounted directories. Fix with:

```bash
sudo chown -R $(whoami):$(whoami) dags/ src/ plugins/ logs/ config/
```

### Port 8080 already in use

Another service is using port 8080. Either stop it, or change the port mapping in `docker-compose.yml`:

```yaml
ports:
  - "8081:8080"    # access UI at localhost:8081 instead
```

### Containers keep restarting

Check the logs for the failing service:

```bash
docker compose logs -f airflow-apiserver
docker compose logs -f airflow-scheduler
```

Common causes:
- Wrong database credentials in `.env`
- Not enough memory (need at least 4GB)
- Port conflicts

### DAG not showing up in the UI

- Wait 30-60 seconds for the dag-processor to parse new files
- Check for syntax errors: `docker compose exec airflow-apiserver python /opt/airflow/dags/your_dag.py`
- Check dag-processor logs: `docker compose logs -f airflow-dag-processor`

### ModuleNotFoundError when importing from src/

- Make sure every directory under `src/` has an `__init__.py` file
- Make sure `PYTHONPATH: /opt/airflow/src` is set in `docker-compose.yml`
- If you added a new pip package, rebuild: `docker compose build && docker compose up -d`

### Worker not picking up tasks

- Check that the worker is healthy: `docker compose ps`
- Check worker logs: `docker compose logs -f airflow-worker`
- Make sure Redis is running: `docker compose exec redis redis-cli ping` (should return `PONG`)

### Changes to DAG or src/ not taking effect

- DAG changes: wait 30-60 seconds for the dag-processor to re-parse, or restart: `docker compose restart airflow-dag-processor`
- `src/` changes: the volume mount reflects changes immediately, but if a module was already imported, restart the worker: `docker compose restart airflow-worker`
- `requirements.txt` changes: requires a full rebuild: `docker compose build && docker compose up -d`

### Database connection errors after changing credentials

If you changed `POSTGRES_USER` or `POSTGRES_PASSWORD` in `.env` but forgot to recreate the volume, the old credentials are still in the database. Fix with:

```bash
docker compose down -v
docker compose up -d
```

### Out of disk space

Airflow logs can grow quickly. Clean up old logs:

```bash
find logs/ -name "*.log" -mtime +7 -delete
```

To reclaim Docker disk space:

```bash
docker system prune -f
```
