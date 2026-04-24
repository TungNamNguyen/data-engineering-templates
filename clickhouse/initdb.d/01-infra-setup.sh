#!/bin/bash
# Creates the bronze/silver/gold databases and the data-engineering service accounts.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"

# Escape ' for SQL literals.
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
