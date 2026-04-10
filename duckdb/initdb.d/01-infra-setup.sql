-- 01-infra-setup.sql — near-no-op for DuckDB.
--
-- The other templates in this repo use the `01-infra-setup` slot for
-- env-injected shell work: creating databases, creating service
-- accounts (`transform_user`, `read_user`), setting the root password.
-- None of that is expressible in DuckDB: it has no multi-database
-- concept (one file is one database), no user or role system, and no
-- root password.
--
-- The target .duckdb file is created implicitly the first time the
-- DuckDB CLI opens it — which the init sidecar does by running this
-- very file via `.read`, so by the time anything in here executes,
-- the file already exists.
--
-- `SELECT 1;` is here only so the file is not empty; `.read` on a
-- zero-byte file is a silent no-op, which would make the init logs
-- confusing.

SELECT 1;
