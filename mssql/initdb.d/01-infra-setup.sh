#!/bin/bash
# Creates MSSQL_DATABASE, the legacy MSSQL_USER (db_owner), and the
# data-engineering logins (transform_user, read_user).

set -euo pipefail

: "${TRANSFORM_USER_PASSWORD:?TRANSFORM_USER_PASSWORD must be set in .env}"
: "${READ_USER_PASSWORD:?READ_USER_PASSWORD must be set in .env}"
: "${MSSQL_SA_PASSWORD:?MSSQL_SA_PASSWORD must be set in .env}"
: "${MSSQL_DATABASE:?MSSQL_DATABASE must be set in .env}"
: "${MSSQL_USER:?MSSQL_USER must be set in .env}"
: "${MSSQL_PASSWORD:?MSSQL_PASSWORD must be set in .env}"

SQLCMD=/opt/mssql-tools18/bin/sqlcmd

# Escape ' for T-SQL literals.
_esc() { printf '%s' "${1//\'/\'\'}"; }
MSSQL_PW_ESC=$(_esc "$MSSQL_PASSWORD")
TRANSFORM_PW_ESC=$(_esc "$TRANSFORM_USER_PASSWORD")
READ_PW_ESC=$(_esc "$READ_USER_PASSWORD")

"$SQLCMD" -S mssql -U sa -P "$MSSQL_SA_PASSWORD" -C -b -Q "
IF DB_ID(N'${MSSQL_DATABASE}') IS NULL CREATE DATABASE [${MSSQL_DATABASE}];

IF SUSER_ID(N'${MSSQL_USER}') IS NULL
    CREATE LOGIN [${MSSQL_USER}] WITH PASSWORD = N'${MSSQL_PW_ESC}', CHECK_POLICY = OFF;

IF SUSER_ID(N'transform_user') IS NULL
    CREATE LOGIN [transform_user] WITH PASSWORD = N'${TRANSFORM_PW_ESC}', CHECK_POLICY = OFF;

IF SUSER_ID(N'read_user') IS NULL
    CREATE LOGIN [read_user] WITH PASSWORD = N'${READ_PW_ESC}', CHECK_POLICY = OFF;
"

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
