-- Runs on first startup only (when the data volume is empty).
-- Creates a sample schema and table to verify the template works end-to-end.

CREATE SCHEMA IF NOT EXISTS example;

CREATE TABLE IF NOT EXISTS example.events (
    event_id    BIGSERIAL PRIMARY KEY,
    event_time  TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id     BIGINT      NOT NULL,
    event_type  TEXT        NOT NULL,
    payload     JSONB       NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS events_event_time_idx
    ON example.events (event_time DESC);

CREATE INDEX IF NOT EXISTS events_user_id_idx
    ON example.events (user_id);

CREATE INDEX IF NOT EXISTS events_payload_gin_idx
    ON example.events USING GIN (payload);
