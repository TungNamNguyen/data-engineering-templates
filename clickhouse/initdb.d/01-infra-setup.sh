#!/bin/bash
# 01-infra-setup.sh — creates the bronze/silver/gold databases and the
# data-engineering service accounts.
#
# ClickHouse has no schema layer between database and table ("SCHEMA" is a
# synonym for "DATABASE"), so the medallion layers manifest as separate
# databases sitting alongside the existing CLICKHOUSE_DB.
#
# Passwords are read from environment variables set in .env, escaped for
# single quotes, and piped to clickhouse-client over stdin. This script
# requires CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 on the server (already
# set in docker-compose.yml) so SQL-driven user management works.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"

# Escape single quotes for SQL string literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

clickhouse-client \
    --host 127.0.0.1 \
    --user "$CLICKHOUSE_USER" \
    --password "$CLICKHOUSE_PASSWORD" \
    --multiquery <<EOSQL
CREATE DATABASE IF NOT EXISTS bronze;
CREATE DATABASE IF NOT EXISTS silver;
CREATE DATABASE IF NOT EXISTS gold;

CREATE USER IF NOT EXISTS transform_user IDENTIFIED WITH sha256_password BY '${TRANSFORM_PW_ESC}';
CREATE USER IF NOT EXISTS read_user      IDENTIFIED WITH sha256_password BY '${READ_PW_ESC}';
EOSQL
