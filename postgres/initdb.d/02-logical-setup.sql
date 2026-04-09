-- 02-logical-setup.sql — creates the bronze/silver/gold layers as schemas
-- inside POSTGRES_DB. Runs after 01-infra-setup.sh, so transform_user exists
-- and can own the schemas outright (no explicit GRANT needed for it in 03).
--
-- Layers follow the medallion architecture:
--   bronze — raw ingested data
--   silver — cleaned / conformed data
--   gold   — curated, business-level aggregates

CREATE SCHEMA IF NOT EXISTS bronze AUTHORIZATION transform_user;
CREATE SCHEMA IF NOT EXISTS silver AUTHORIZATION transform_user;
CREATE SCHEMA IF NOT EXISTS gold   AUTHORIZATION transform_user;
