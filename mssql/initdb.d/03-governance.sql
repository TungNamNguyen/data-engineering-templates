-- Grants read_user SELECT on bronze/silver/gold (covers existing + future tables).

GRANT SELECT ON SCHEMA::bronze TO [read_user];
GRANT SELECT ON SCHEMA::silver TO [read_user];
GRANT SELECT ON SCHEMA::gold   TO [read_user];
GO
