-- Grants transform_user ALL and read_user SELECT on bronze/silver/gold.

GRANT ALL PRIVILEGES ON bronze.* TO 'transform_user'@'%';
GRANT ALL PRIVILEGES ON silver.* TO 'transform_user'@'%';
GRANT ALL PRIVILEGES ON gold.*   TO 'transform_user'@'%';

GRANT SELECT ON bronze.* TO 'read_user'@'%';
GRANT SELECT ON silver.* TO 'read_user'@'%';
GRANT SELECT ON gold.*   TO 'read_user'@'%';

FLUSH PRIVILEGES;
