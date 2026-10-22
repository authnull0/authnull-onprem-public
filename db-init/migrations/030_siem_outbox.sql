-- SIEM outbox, in each ORGANISATION database: security events on their way to
-- the organisation's SIEM.
--
-- WHY
--
-- SSH gateway and control-plane events (sessions, refusals, key releases,
-- endpoint lifecycle) go to the SIEM each tenant configures in Logs Config,
-- through the on-prem Fluent Bit. Fluent Bit buffers once it has an event; this
-- table covers the step before: an event is written here in the same breath as
-- the thing it reports, and the forwarder moves it to Fluent Bit, retrying
-- while Fluent Bit restarts or is unreachable.
--
-- event_id is unique: a gateway that re-sends a batch it is unsure was received
-- adds nothing twice, and the SIEM can deduplicate on the same id.
--
-- Rows are deleted a day after they are sent; one never sent goes after seven
-- days, so an organisation with no SIEM -- or one down for a week -- does not
-- grow this table without bound.
--
-- Numbered 030, following 029_recording_storage.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.siem_outbox (
    id         bigserial   PRIMARY KEY,
    event_id   uuid        NOT NULL UNIQUE,
    log_type   text        NOT NULL DEFAULT 'ssh',
    body       jsonb       NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at    timestamptz
);

CREATE INDEX IF NOT EXISTS siem_outbox_unsent
    ON did.siem_outbox (id)
    WHERE sent_at IS NULL;