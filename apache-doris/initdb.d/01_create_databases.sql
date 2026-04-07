-- Creates databases and users on first startup.
-- Root password is set via docker-compose entrypoint from .env (DORIS_ROOT_PASSWORD).
-- Modify for your own project.

CREATE DATABASE IF NOT EXISTS example_db;

-- Sample user with read/write access to example_db
CREATE USER IF NOT EXISTS 'dev'@'%' IDENTIFIED BY 'dev123';
GRANT ALL ON example_db TO 'dev'@'%';
