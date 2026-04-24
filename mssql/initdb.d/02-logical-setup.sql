-- Creates the bronze/silver/gold schemas owned by transform_user.
-- EXEC() is required because CREATE SCHEMA must be the first statement in a batch.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'bronze')
    EXEC('CREATE SCHEMA [bronze] AUTHORIZATION [transform_user]');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'silver')
    EXEC('CREATE SCHEMA [silver] AUTHORIZATION [transform_user]');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'gold')
    EXEC('CREATE SCHEMA [gold] AUTHORIZATION [transform_user]');
GO
