-- Creates the bronze/silver/gold schemas owned by transform_user.

CREATE SCHEMA IF NOT EXISTS bronze AUTHORIZATION transform_user;
CREATE SCHEMA IF NOT EXISTS silver AUTHORIZATION transform_user;
CREATE SCHEMA IF NOT EXISTS gold   AUTHORIZATION transform_user;
