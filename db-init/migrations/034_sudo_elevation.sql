-- Sudo elevation, in each ORGANISATION database.
--
-- WHAT
--
-- An administrator grants one operator sudo on one account of one endpoint:
-- "aditya@ may elevate to sshtest on web-vm-01, for these commands (or full
-- sudo), until Friday". That is a did.sudo_grants row. Nothing is installed on
-- the endpoint when it is created.
--
-- When that operator opens an SSH session to that account through the gateway
-- and approves its push, the control plane -- releasing the session's key --
-- records a did.sudo_elevations row and queues a grant_sudo job. The gateway
-- runs it at once: the endpoint helper writes /etc/sudoers.d/authnull-sudo-<account>
-- (checked with visudo) and schedules its own removal at the elevation's expiry.
-- When the session ends, or the elevation expires, or the grant is revoked, a
-- revoke_sudo job removes the file and ends any root process the account's
-- logins still run.
--
-- RULES
--
--   * Elevation needs a second factor: only a decision made with an MFA
--     challenge (did.ssh_decisions.mfa_challenge_ref) elevates.
--   * One live elevation per account per endpoint. While an account is
--     elevated, a second session to it is refused: sudo belongs to the Unix
--     account, so anyone else in it would hold the same rights.
--   * An elevation never outlives its grant, nor max_minutes.
--
-- Numbered 034, following 033_splunk_tls_skip_verify.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.sudo_grants (
    id               uuid        PRIMARY KEY,
    org_id           integer     NOT NULL,
    endpoint_id      bigint      NOT NULL,
    account          text        NOT NULL,
    operator_user_id integer,
    operator_email   text        NOT NULL,
    full_sudo        boolean     NOT NULL DEFAULT false,
    commands         jsonb       NOT NULL DEFAULT '[]'::jsonb,
    max_minutes      integer     NOT NULL DEFAULT 60 CHECK (max_minutes BETWEEN 5 AND 720),
    valid_from       timestamptz NOT NULL DEFAULT now(),
    valid_until      timestamptz,
    reason           text,
    status           text        NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
    created_by       integer,
    created_at       timestamptz NOT NULL DEFAULT now(),
    revoked_at       timestamptz,
    revoked_by       integer,
    revoked_reason   text,
    CHECK (full_sudo OR jsonb_array_length(commands) > 0)
);

CREATE INDEX IF NOT EXISTS sudo_grants_by_slot
    ON did.sudo_grants (org_id, endpoint_id, account) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS did.sudo_elevations (
    id             uuid        PRIMARY KEY,
    org_id         integer     NOT NULL,
    grant_id       uuid        NOT NULL REFERENCES did.sudo_grants (id),
    endpoint_id    bigint      NOT NULL,
    jump_server_id integer     NOT NULL,
    account        text        NOT NULL,
    session_id     text        NOT NULL,
    decision_id    text        NOT NULL,
    operator_email text        NOT NULL,
    full_sudo      boolean     NOT NULL,
    commands       jsonb       NOT NULL,
    status         text        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending', 'active', 'ended', 'failed')),
    expires_at     timestamptz NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    installed_at   timestamptz,
    ended_at       timestamptz,
    end_reason     text,
    removed_at     timestamptz
);

-- One live elevation per account per endpoint.
CREATE UNIQUE INDEX IF NOT EXISTS sudo_elevations_one_live
    ON did.sudo_elevations (org_id, endpoint_id, account) WHERE status IN ('pending', 'active');
CREATE INDEX IF NOT EXISTS sudo_elevations_by_session
    ON did.sudo_elevations (org_id, session_id);
CREATE INDEX IF NOT EXISTS sudo_elevations_by_time
    ON did.sudo_elevations (org_id, created_at DESC);

-- gateway_jobs_kind_check is owned by 042_admin_account.sql; see the note there.

-- The endpoint helper's version, read by each account scan. Sudo elevation
-- needs version 2; an endpoint set up before it shows "re-run setup".
ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS helper_version integer;
