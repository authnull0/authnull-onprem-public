-- 040_temp_users.sql
--
-- Temporary users: a local account created on an endpoint for one approved SSH
-- session and deleted when it ends.
--
-- An Endpoint Policy that lists the reserved account "temp" lets its operators
-- connect as `temp@host@gateway`. When such a session is approved, the control
-- plane names the operator's account on that endpoint (an-<name>-<hash>), makes
-- a key for the session, records a did.temp_users row and queues a
-- temp_user_add job. The gateway runs it at once: the endpoint helper creates
-- the account (no password, locked), installs the session's public key, and
-- schedules the account's removal at the row's expiry, so it cannot outlive it
-- if the gateway goes away. The gateway then logs in as that account with that
-- key. When the session ends -- or expires -- a temp_user_del job removes the
-- session's key, and the account itself once no other session uses it.
--
-- Numbered 040, following 039_sso_providers.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.temp_users (
    id              uuid        PRIMARY KEY,
    org_id          integer     NOT NULL,
    endpoint_id     bigint      NOT NULL,
    jump_server_id  integer     NOT NULL,
    account         text        NOT NULL,
    operator_email  text        NOT NULL,
    operator_id     integer,
    session_id      text        NOT NULL,
    decision_id     text,
    key_fingerprint text        NOT NULL,
    status          text        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'active', 'ended', 'failed')),
    expires_at      timestamptz NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    active_at       timestamptz,
    ended_at        timestamptz,
    end_reason      text,
    removed_at      timestamptz
);
CREATE INDEX IF NOT EXISTS temp_users_by_endpoint ON did.temp_users (org_id, endpoint_id, created_at DESC);
CREATE INDEX IF NOT EXISTS temp_users_by_session ON did.temp_users (org_id, session_id);
CREATE INDEX IF NOT EXISTS temp_users_live ON did.temp_users (org_id, jump_server_id, expires_at)
    WHERE status IN ('pending', 'active');

-- gateway_jobs_kind_check is owned by 042_admin_account.sql; see the note there.
