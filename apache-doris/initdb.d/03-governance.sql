-- Grants transform_user ALL and read_user SELECT_PRIV on bronze/silver/gold.

GRANT ALL ON bronze.* TO 'transform_user';
GRANT ALL ON silver.* TO 'transform_user';
GRANT ALL ON gold.*   TO 'transform_user';

GRANT SELECT_PRIV ON bronze.* TO 'read_user';
GRANT SELECT_PRIV ON silver.* TO 'read_user';
GRANT SELECT_PRIV ON gold.*   TO 'read_user';
