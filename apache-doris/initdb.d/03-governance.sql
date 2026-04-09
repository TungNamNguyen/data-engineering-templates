-- 03-governance.sql — grants privileges to the service accounts.
--
-- transform_user: full privileges on bronze/silver/gold (can CREATE,
--                 ALTER, DROP, INSERT, SELECT — the works).
-- read_user:      SELECT only on all three layers.
--
-- Doris follows the MySQL grant model: `db.*` covers existing AND
-- future tables/views in that database, so no additional mechanism is
-- needed for newly created tables.

GRANT ALL ON bronze.* TO 'transform_user';
GRANT ALL ON silver.* TO 'transform_user';
GRANT ALL ON gold.*   TO 'transform_user';

GRANT SELECT_PRIV ON bronze.* TO 'read_user';
GRANT SELECT_PRIV ON silver.* TO 'read_user';
GRANT SELECT_PRIV ON gold.*   TO 'read_user';
