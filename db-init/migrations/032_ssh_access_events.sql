-- SSH access events, in each ORGANISATION database: what each gateway reported
-- about each connection -- decisions, refusals, session start and end, stored
-- recordings -- kept for the console's SSH access log.
--
-- WHY
--
-- The access log shows one row per SSH access attempt, assembled from the
-- decision (did.ssh_decisions, written by authn-service), the recording
-- (did.jump_server_recordings) and these events. A connection refused at the
-- gateway -- no certificate, a target that is not one of its endpoints --
-- never reaches the decision service, so these events are its only record.
-- The SIEM outbox (030) holds the same events only until they are delivered;
-- this table is the console's own copy, kept whether or not a SIEM is
-- configured.
--
-- event_id is the gateway's: a batch sent twice is stored once.
-- Rows older than SSH_ACCESS_LOG_DAYS (default 180) are deleted hourly.
--
-- Numbered 032, following 031_siem_output_secrets.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.ssh_access_events (
    event_id        uuid        PRIMARY KEY,
    org_id          integer     NOT NULL,
    jump_server_id  integer     NOT NULL,
    event_type      text        NOT NULL,
    outcome         text        NOT NULL,
    reason          text,
    session_id      text,
    decision_id     text,
    principal       text,
    key_fingerprint text,
    src_ip          text,
    target_host     text,
    target_account  text,
    details         jsonb,
    occurred_at     timestamptz NOT NULL,
    received_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ssh_access_events_by_time
    ON did.ssh_access_events (org_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS ssh_access_events_by_session
    ON did.ssh_access_events (session_id)
    WHERE session_id IS NOT NULL;
