-- Runs on first startup only (when the data volume is empty).
-- Creates a sample table to verify the template works end-to-end.
--
-- The MYSQL_DATABASE from .env (default: `app`) is already created and selected
-- by the entrypoint, so no `CREATE DATABASE` / `USE` is needed here.

CREATE TABLE IF NOT EXISTS events (
    event_id    BIGINT       NOT NULL AUTO_INCREMENT,
    event_time  TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    user_id     BIGINT       NOT NULL,
    event_type  VARCHAR(64)  NOT NULL,
    payload     JSON         NOT NULL,
    PRIMARY KEY (event_id),
    KEY events_event_time_idx (event_time),
    KEY events_user_id_idx (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
