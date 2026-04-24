#!/bin/bash
# Creates the data-engineering service accounts (transform_user, read_user).

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
