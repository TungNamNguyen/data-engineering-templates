#!/bin/bash
# 01-infra-setup.sh — creates the target database, the legacy MSSQL_USER
# (kept for backwards compatibility), and the data-engineering service
# accounts (transform_user, read_user).
#
# Runs inside the mssql-init sidecar, which provides sqlcmd and has
# MSSQL_SA_PASSWORD / MSSQL_DATABASE / MSSQL_USER / MSSQL_PASSWORD /
# TRANSFORM_USER_PASSWORD / READ_USER_PASSWORD in its environment.
#
# Passwords are escaped for single quotes and embedded into T-SQL sent
# via sqlcmd's -Q. The SA password is passed through -P only inside the
# sidecar's isolated process namespace, which is an acceptable trade-off
# given that sqlcmd has no env-based password mechanism equivalent to
# psql's :'var' binding.

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set in .env}"
: "${MSSQL_DATABASE:?MSSQL_DATABASE must be set in .env}"
: "${MSSQL_USER:?MSSQL_USER must be set in .env}"
: "${MSSQL_PASSWORD:?MSSQL_PASSWORD must be set in .env}"

SQLCMD=/opt/mssql-tools18/bin/sqlcmd

# Escape single quotes for T-SQL string literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
MSSQL_PW_ESC=$(_esc "$MSSQL_PASSWORD")
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

# Step 1 — server-level: database + all logins.
"$SQLCMD" -S mssql -U sa -P "$MSSQL_SA_PASSWORD" -C -b -Q "
IF DB_ID(N'${MSSQL_DATABASE}') IS NULL CREATE DATABASE [${MSSQL_DATABASE}];

IF SUSER_ID(N'${MSSQL_USER}') IS NULL
    CREATE LOGIN [${MSSQL_USER}] WITH PASSWORD = N'${MSSQL_PW_ESC}', CHECK_POLICY = OFF;

IF SUSER_ID(N'transform_user') IS NULL
    CREATE LOGIN [transform_user] WITH PASSWORD = N'${TRANSFORM_PW_ESC}', CHECK_POLICY = OFF;

IF SUSER_ID(N'read_user') IS NULL
    CREATE LOGIN [read_user] WITH PASSWORD = N'${READ_PW_ESC}', CHECK_POLICY = OFF;
"

# Step 2 — database-level: map each login to a user in MSSQL_DATABASE and
# grant the db-level CREATE permissions transform_user needs to add tables,
# views, and procedures. (Owning a schema is necessary but not sufficient
# in SQL Server — CREATE TABLE is a database-scoped permission that gates
# WHICH databases you can create in; schema ownership then gates WHERE
# within those databases. transform_user has both; read_user has neither.)
# The legacy MSSQL_USER keeps its db_owner role for backwards compatibility
# with the previous template.
"$SQLCMD" -S mssql -U sa -P "$MSSQL_SA_PASSWORD" -C -b -d "$MSSQL_DATABASE" -Q "
IF USER_ID(N'${MSSQL_USER}') IS NULL CREATE USER [${MSSQL_USER}] FOR LOGIN [${MSSQL_USER}];
EXEC sp_addrolemember N'db_owner', N'${MSSQL_USER}';

IF USER_ID(N'transform_user') IS NULL CREATE USER [transform_user] FOR LOGIN [transform_user];
GRANT CREATE TABLE     TO [transform_user];
GRANT CREATE VIEW      TO [transform_user];
GRANT CREATE PROCEDURE TO [transform_user];
GRANT CREATE FUNCTION  TO [transform_user];

IF USER_ID(N'read_user') IS NULL CREATE USER [read_user] FOR LOGIN [read_user];
"
