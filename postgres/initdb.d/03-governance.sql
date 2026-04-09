-- 03-governance.sql — grants privileges to the service accounts.
--
-- transform_user owns the bronze/silver/gold schemas (set in 02), so it has
-- all privileges on them implicitly. This file only needs to grant read_user
-- what it should see, plus default privileges so future tables created by
-- transform_user automatically become visible to read_user.

-- read_user: enter the schema and SELECT existing tables/views
GRANT USAGE ON SCHEMA bronze, silver, gold TO read_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bronze, silver, gold TO read_user;

-- read_user: auto-SELECT on any FUTURE tables transform_user creates.
-- This is the crucial bit — without it, every new table would need a
-- manual GRANT. Default privileges attach per-creator-role, which is why
-- we scope them to transform_user.
ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA bronze
    GRANT SELECT ON TABLES TO read_user;
ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA silver
    GRANT SELECT ON TABLES TO read_user;
ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA gold
    GRANT SELECT ON TABLES TO read_user;
