# MinIO

Object storage server compatible with the Amazon S3 API.

## Services

| Service | Port | Description |
|---------|------|-------------|
| MinIO API | 9000 | S3-compatible API endpoint |
| MinIO Console | 9001 | Web-based management UI |

## Quick Start

1. Copy the environment file and configure your credentials:

```bash
cp .env.example .env
```

2. Start the services:

```bash
docker compose up -d
```

3. Open the MinIO Console at [http://localhost:9001](http://localhost:9001) and log in with the credentials from your `.env` file.

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `MINIO_ROOT_USER` | Admin username | `minioadmin` |
| `MINIO_ROOT_PASSWORD` | Admin password | `minioadmin` |

## Data Persistence

Data is stored in a named Docker volume `minio_data`. To reset all data:

```bash
docker compose down -v
```

## Example Script

`example.py` shows how to interact with MinIO in several ways:

```bash
pip install minio pandas pyarrow deltalake pyiceberg
python example.py
```

What it covers:

| Function | Format | How it talks to MinIO |
|----------|--------|-----------------------|
| `upload_text` | plain text | `minio` SDK — `put_object` |
| `upload_csv` | CSV | `minio` SDK — `put_object` |
| `upload_parquet` | Parquet | `minio` SDK — `put_object` |
| `upload_json` | JSON | `minio` SDK — `put_object` |
| `write_delta` / `read_delta` | Delta Lake | `deltalake` — talks to MinIO via `s3://` paths |
| `write_iceberg` / `read_iceberg` | Apache Iceberg | `pyiceberg` — SQLite catalog + MinIO as `s3://` storage |

Delta Lake and Iceberg don't use the MinIO client directly. They use S3-compatible storage options to read/write via `s3://` paths, which is why `example.py` defines an `S3_OPTS` dict with endpoint, credentials, and a dummy `AWS_REGION` (required by the underlying S3 libraries, ignored by MinIO).

## Usage with AWS CLI

```bash
aws --endpoint-url http://localhost:9000 s3 mb s3://my-bucket
aws --endpoint-url http://localhost:9000 s3 cp myfile.txt s3://my-bucket/
```
