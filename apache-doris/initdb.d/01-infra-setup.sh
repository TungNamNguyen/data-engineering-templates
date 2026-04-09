#!/bin/bash
# 01-infra-setup.sh — sets the Doris root password from env, then creates
# the bronze/silver/gold databases and the data-engineering service
# accounts.
#
# Runs inside the `doris-init` sidecar, which has a mysql client and can
# reach the FE on the Doris subnet. DORIS_FE_HOST and DORIS_FE_PORT are
# exported by the sidecar. DORIS_ROOT_PASSWORD may be empty (local dev).
#
# Doris has no schema layer between database and table (it follows the
# MySQL model), so the medallion layers manifest as separate databases.
#
# Passwords are escaped for single quotes and piped to mysql via stdin.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"
: "${DORIS_FE_HOST:?DORIS_FE_HOST must be set}"
: "${DORIS_FE_PORT:?DORIS_FE_PORT must be set}"

# Escape single quotes for SQL string literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
ROOT_PW_ESC=$(_esc "${DORIS_ROOT_PASSWORD:-}")
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

# Step 1 — on a fresh Doris cluster, root has no password. Set it to the
# env-supplied value (which may be empty for local dev: ALTER USER to an
# empty password is a no-op and is safe to re-run).
mysql -h "$DORIS_FE_HOST" -P "$DORIS_FE_PORT" -u root <<EOSQL
ALTER USER 'root'@'%' IDENTIFIED BY '${ROOT_PW_ESC}';
EOSQL

# Step 2 — reconnect using the (possibly new) password and create the
# layers and service accounts.
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
