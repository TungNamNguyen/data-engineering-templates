-- 03-governance.sql — grants privileges to the service accounts.
--
-- transform_user: full privileges on bronze/silver/gold (can CREATE, ALTER,
--                 DROP, INSERT, UPDATE, DELETE, SELECT — the works).
-- read_user:      SELECT only on all three layers.
--
-- MySQL's `db.*` wildcard covers existing AND future tables/views in that
-- database, so no "default privileges" mechanism is needed here.

GRANT ALL PRIVILEGES ON bronze.* TO 'transform_user'@'%';
GRANT ALL PRIVILEGES ON silver.* TO 'transform_user'@'%';
GRANT ALL PRIVILEGES ON gold.*   TO 'transform_user'@'%';

GRANT SELECT ON bronze.* TO 'read_user'@'%';
GRANT SELECT ON silver.* TO 'read_user'@'%';
GRANT SELECT ON gold.*   TO 'read_user'@'%';

FLUSH PRIVILEGES;
