-- 02-logical-setup.sql — creates the medallion schema layers.
--
-- DuckDB has first-class schema support (like Postgres), so the
-- bronze / silver / gold layers live as real schemas inside the single
-- .duckdb file, not as separate databases.
--
-- Idempotent — re-runs harmlessly on every `docker compose up -d`.

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
