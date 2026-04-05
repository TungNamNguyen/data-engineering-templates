# Data Engineering Templates

A collection of production-ready Docker Compose templates and configurations for common data engineering tools.

## Templates

| Tool | Description | Version | Status |
|------|-------------|---------|--------|
| [Airflow](airflow/) | Workflow orchestration (CeleryExecutor, PostgreSQL, Redis) | 3.1.8 | Ready |
| [MinIO](minio/) | S3-compatible object storage with Delta Lake and Iceberg examples | latest | Ready |

## How to Use

1. Navigate to a template directory
2. Copy `.env.example` to `.env` and configure your credentials
3. Build and start:

```bash
cd <template>/
cp .env.example .env
docker compose build
docker compose up -d
```

Each template includes its own `README.md` with detailed setup instructions.

## Project Structure

Each template is self-contained in its own directory with:
- `docker-compose.yml` — full stack definition
- `Dockerfile` — custom image with your dependencies
- `.env.example` — template for environment variables (safe to commit)
- `.env` — your local credentials (gitignored)
- `requirements.txt` — Python dependencies (where applicable)
- `README.md` — step-by-step setup guide
