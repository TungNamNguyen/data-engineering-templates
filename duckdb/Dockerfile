# DuckDB — minimal container with just the DuckDB CLI.
#
# DuckDB is an embedded database (like SQLite), not a client-server system,
# so this image is intentionally tiny: one statically-linked binary on top
# of debian:bookworm-slim. Everything else — init, lifecycle — lives in
# docker-compose.yml.

FROM debian:bookworm-slim

ARG DUCKDB_VERSION=1.2.2

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip \
 && ARCH=$(uname -m) \
 && case "$ARCH" in \
      x86_64)  DUCKDB_ARCH=amd64 ;; \
      aarch64) DUCKDB_ARCH=arm64 ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
 && wget -q "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-${DUCKDB_ARCH}.zip" -O /tmp/duckdb.zip \
 && unzip /tmp/duckdb.zip -d /usr/local/bin/ \
 && chmod +x /usr/local/bin/duckdb \
 && rm /tmp/duckdb.zip \
 && apt-get purge -y --auto-remove wget unzip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /data
