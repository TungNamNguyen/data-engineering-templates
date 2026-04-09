#!/bin/bash
# 01-infra-setup.sh — creates the data-engineering service accounts.
#
# Runs on first startup only (empty data volume). Passwords are read from
# environment variables set in .env and injected via psql's variable binding
# (the :'var' syntax safely quotes and escapes the value), so secrets never
# appear on the command line or in logs.
#
# Users created:
#   transform_user  — owns the bronze/silver/gold schemas (created in 02)
#   read_user       — read-only access (granted in 03)

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"

psql -v ON_ERROR_STOP=1 \
     -v transform_pw="$TRANSFORM_USER_PASSWORD" \
     -v read_pw="$READ_USER_PASSWORD" \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" <<-'EOSQL'
    CREATE USER transform_user WITH LOGIN PASSWORD :'transform_pw';
    CREATE USER read_user      WITH LOGIN PASSWORD :'read_pw';
EOSQL
