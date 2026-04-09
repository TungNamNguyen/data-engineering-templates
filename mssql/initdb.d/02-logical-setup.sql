-- 02-logical-setup.sql — creates the bronze/silver/gold layers as schemas
-- inside MSSQL_DATABASE. Runs after 01-infra-setup.sh, so the database
-- and users already exist.
--
-- T-SQL does not support IF NOT EXISTS on CREATE SCHEMA directly, so we
-- check sys.schemas and use dynamic SQL (CREATE SCHEMA must be the first
-- statement in a batch, hence EXEC()).
--
-- Layers follow the medallion architecture:
--   bronze — raw ingested data
--   silver — cleaned / conformed data
--   gold   — curated, business-level aggregates

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'bronze')
    EXEC('CREATE SCHEMA [bronze] AUTHORIZATION [transform_user]');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'silver')
    EXEC('CREATE SCHEMA [silver] AUTHORIZATION [transform_user]');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'gold')
    EXEC('CREATE SCHEMA [gold] AUTHORIZATION [transform_user]');
GO
