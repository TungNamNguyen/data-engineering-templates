#!/bin/bash
# Creates the bronze/silver/gold databases and the data-engineering service accounts.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"

# Escape ' for SQL literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --protocol=socket -u root <<EOSQL
CREATE DATABASE IF NOT EXISTS bronze CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS silver CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS gold   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

CREATE USER IF NOT EXISTS 'transform_user'@'%' IDENTIFIED BY '${TRANSFORM_PW_ESC}';
CREATE USER IF NOT EXISTS 'read_user'@'%'      IDENTIFIED BY '${READ_PW_ESC}';
EOSQL
