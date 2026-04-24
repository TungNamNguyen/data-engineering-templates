#!/bin/bash
# Sets the Doris root password, then creates the bronze/silver/gold
# databases and the data-engineering service accounts.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"
: "${DORIS_FE_HOST:?DORIS_FE_HOST must be set}"
: "${DORIS_FE_PORT:?DORIS_FE_PORT must be set}"

# Escape ' for SQL literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
ROOT_PW_ESC=$(_esc "${DORIS_ROOT_PASSWORD:-}")
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

# A fresh Doris cluster has no root password; set it (empty value is a safe no-op).
mysql -h "$DORIS_FE_HOST" -P "$DORIS_FE_PORT" -u root <<EOSQL
ALTER USER 'root'@'%' IDENTIFIED BY '${ROOT_PW_ESC}';
EOSQL

_MYSQL_OPTS=(-h "$DORIS_FE_HOST" -P "$DORIS_FE_PORT" -u root)
if [ -n "${DORIS_ROOT_PASSWORD:-}" ]; then
    _MYSQL_OPTS+=(-p"$DORIS_ROOT_PASSWORD")
fi

mysql "${_MYSQL_OPTS[@]}" <<EOSQL
CREATE DATABASE IF NOT EXISTS bronze;
CREATE DATABASE IF NOT EXISTS silver;
CREATE DATABASE IF NOT EXISTS gold;

CREATE USER IF NOT EXISTS 'transform_user' IDENTIFIED BY '${TRANSFORM_PW_ESC}';
CREATE USER IF NOT EXISTS 'read_user'      IDENTIFIED BY '${READ_PW_ESC}';
EOSQL
