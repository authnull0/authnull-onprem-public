-- SSH decisions, in each ORGANISATION database: one row per decision authn-service
-- makes for an SSH session, and what it released.
--
-- WHY
--
-- A grant's key is in the vault (024). Step 7 opens a session with it, released
-- only after the session was allowed -- and the control plane has to see that
-- for itself rather than take a gateway's word for it. authn-service writes this
-- row when it decides; the gateway then asks for the session's key by the row's
-- id, and the control plane releases it only if:
--
--   * the decision allowed the session,
--   * it was made for the gateway asking (jump_server_id, from the gateway's
--     verified token -- never from the request body),
--   * it names the session the gateway says it is opening,
--   * it is under two minutes old, and
--   * nothing has been released for it before (credential_released_at).
--
-- One decision, one release, one session.
--
-- WRITERS
--
--   authn-service   inserts, once per decision.
--   authnull-service sets credential_released_at and released_grant_id.
--
-- Numbered 025, following 024_ssh_grants.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.ssh_decisions (
    id                     uuid        PRIMARY KEY,
    org_id                 integer     NOT NULL,
    jump_server_id         integer,
    session_id             text        NOT NULL,
    user_id                integer,
    email                  text,
    target_host            text        NOT NULL,
    target_account         text        NOT NULL,
    outcome                text        NOT NULL CHECK (outcome IN ('allow', 'deny')),
    reason                 text,
    mfa_challenge_ref      text,
    decided_at             timestamptz NOT NULL DEFAULT now(),
    credential_released_at timestamptz,
    released_grant_id      uuid
);

CREATE INDEX IF NOT EXISTS ssh_decisions_by_time ON did.ssh_decisions (org_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS ssh_decisions_by_session ON did.ssh_decisions (org_id, session_id);