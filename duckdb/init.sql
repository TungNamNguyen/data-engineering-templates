-- init.sql — runs on every `docker compose up` via the compose `command:`.
-- Idempotent by design (CREATE ... IF NOT EXISTS), so there's no init
-- marker to manage. Layers follow the medallion convention: bronze = raw,
-- silver = cleaned, gold = curated.

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;
