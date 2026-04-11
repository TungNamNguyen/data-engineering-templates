# Data Engineering Templates

A collection of production-ready Docker Compose templates and configurations for common data engineering tools.

## Templates

| Tool | Description | Version | Status |
|------|-------------|---------|--------|
| [Apache Airflow](apache-airflow/) | Workflow orchestration for data pipelines | 3.1.8 | Ready |
| [Apache Doris](apache-doris/) | Real-time analytical database, MySQL-compatible | 3.0.3 | Ready |
| [Apache Superset](apache-superset/) | BI tool for exploring data and building dashboards | 4.1.1 | Ready |
| [ClickHouse](clickhouse/) | Columnar database for real-time analytics | 24.8 | Ready |
| [DuckDB](duckdb/) | In-process analytical database, like SQLite for analytics | 1.2.2 | Ready |
| [MinIO](minio/) | S3-compatible object storage | latest | Ready |
| [Microsoft SQL Server](mssql/) | Microsoft's enterprise relational database | 2022 | Ready |
| [MySQL](mysql/) | The world's most popular open-source relational database | 8.4 LTS | Ready |
| [PostgreSQL](postgres/) | Open-source relational database with a rich extension ecosystem | 16 | Ready |
| [JupyterLab](jupyter-lab/) | Interactive notebook environment for data exploration | latest | Ready |
| [Metabase](metabase/) | BI tool for asking questions about your data | 0.52.4 | Ready |

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
