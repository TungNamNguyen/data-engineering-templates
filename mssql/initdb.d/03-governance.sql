-- 03-governance.sql — grants privileges to the data-engineering users.
--
-- transform_user already OWNS the bronze/silver/gold schemas (set via
-- AUTHORIZATION in 02), which gives it implicit full control — no
-- additional GRANT is needed.
--
-- read_user needs SELECT on each schema. SELECT on a schema covers
-- existing AND future tables/views in that schema, so no default-
-- privileges mechanism is required.

GRANT SELECT ON SCHEMA::bronze TO [read_user];
GRANT SELECT ON SCHEMA::silver TO [read_user];
GRANT SELECT ON SCHEMA::gold   TO [read_user];
GO
