#!/bin/bash
# 01-infra-setup.sh — creates the bronze/silver/gold databases and the
# data-engineering service accounts.
#
# MySQL has no schema layer between database and table (SCHEMA is a synonym
# for DATABASE), so the medallion layers manifest as separate databases
# sitting alongside the existing MYSQL_DATABASE.
#
# Passwords are read from environment variables set in .env, escaped for
# single quotes, and piped to the mysql client over stdin (never passed on
# the command line). The root password is passed via MYSQL_PWD instead of
# `-p` so it never appears in process listings.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"

# Escape single quotes for SQL string literals (MySQL SQL mode).
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
