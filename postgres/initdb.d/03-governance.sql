-- Grants read_user SELECT on bronze/silver/gold, plus default privileges
-- so future tables created by transform_user stay readable.

GRANT USAGE ON SCHEMA bronze, silver, gold TO read_user;
GRANT SELECT ON ALL TABLES IN SCHEMA bronze, silver, gold TO read_user;

ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA bronze
    GRANT SELECT ON TABLES TO read_user;
ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA silver
    GRANT SELECT ON TABLES TO read_user;
ALTER DEFAULT PRIVILEGES FOR ROLE transform_user IN SCHEMA gold
    GRANT SELECT ON TABLES TO read_user;
