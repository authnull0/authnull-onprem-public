-- Password rotation for local accounts, in each ORGANISATION database.
--
-- WHY
--
-- Logins through the gateway never use passwords, but a local password is a
-- door that does not go through it: password SSH straight to the machine, the
-- VM console, su. Rotation makes every such password random, known to nobody,
-- and held in the vault for break-glass.
--
-- WHAT
--
--   * did.password_policies: rotate these accounts (or every scanned one) on
--     these endpoints every N days, at this length and complexity; root only
--     when include_root is set. An account with no usable password (locked,
--     key-only) is left locked -- setting one would open a door -- except root
--     under include_root, which is the break-glass password.
--   * did.password_accounts: one row per (endpoint, account) a policy manages:
--     when it was last rotated, when it is due, and why it failed or was
--     skipped. Due rotations are queued from the gateway's heartbeat.
--   * A rotation is two-step so a password is never lost: the gateway stores
--     the new password as account_password_staged, sets it on the machine, and
--     only then is it promoted to account_password. A rotation that fails
--     before the machine changed leaves the current password as it was.
--   * did.password_reveals: an administrator's break-glass reveal, behind an
--     MFA push, shown once. The account is rotated again
--     rerotate_after_reveal_minutes later, so a revealed password does not
--     stay valid.
--
-- Numbered 035, following 034_sudo_elevation.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.password_policies (
    id                            uuid        PRIMARY KEY,
    org_id                        integer     NOT NULL,
    name                          text        NOT NULL,
    status                        text        NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused')),
    endpoint_ids                  jsonb       NOT NULL DEFAULT '[]'::jsonb,
    accounts                      jsonb       NOT NULL DEFAULT '[]'::jsonb,
    include_root                  boolean     NOT NULL DEFAULT false,
    interval_days                 integer     NOT NULL DEFAULT 30 CHECK (interval_days BETWEEN 1 AND 365),
    length                        integer     NOT NULL DEFAULT 24 CHECK (length BETWEEN 12 AND 128),
    upper                         boolean     NOT NULL DEFAULT true,
    lower                         boolean     NOT NULL DEFAULT true,
    digits                        boolean     NOT NULL DEFAULT true,
    special                       boolean     NOT NULL DEFAULT true,
    rerotate_after_reveal_minutes integer     NOT NULL DEFAULT 60 CHECK (rerotate_after_reveal_minutes BETWEEN 5 AND 1440),
    created_by                    integer,
    created_at                    timestamptz NOT NULL DEFAULT now(),
    updated_by                    integer,
    updated_at                    timestamptz NOT NULL DEFAULT now(),
    CHECK (upper OR lower OR digits OR special)
);

CREATE TABLE IF NOT EXISTS did.password_accounts (
    org_id      integer     NOT NULL,
    endpoint_id bigint      NOT NULL,
    account     text        NOT NULL,
    policy_id   uuid,
    status      text        NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'managed', 'no_password', 'failed')),
    detail      text,
    rotated_at  timestamptz,
    next_due_at timestamptz NOT NULL DEFAULT now(),
    rerotate_at timestamptz,
    revealed_at timestamptz,
    revealed_by integer,
    last_job_id text,
    failures    integer     NOT NULL DEFAULT 0,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (org_id, endpoint_id, account)
);

CREATE TABLE IF NOT EXISTS did.password_reveals (
    id           uuid        PRIMARY KEY,
    org_id       integer     NOT NULL,
    endpoint_id  bigint      NOT NULL,
    account      text        NOT NULL,
    user_id      integer     NOT NULL,
    email        text        NOT NULL,
    challenge_id integer     NOT NULL,
    status       text        NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending', 'approved', 'denied', 'expired', 'shown')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    resolved_at  timestamptz
);
CREATE INDEX IF NOT EXISTS password_reveals_by_time ON did.password_reveals (org_id, created_at DESC);

ALTER TABLE did.vault_secrets DROP CONSTRAINT IF EXISTS vault_secrets_kind_check;
ALTER TABLE did.vault_secrets ADD CONSTRAINT vault_secrets_kind_check
    CHECK (kind IN ('reconcile_key', 'grant_password', 'grant_key', 'storage_credential', 'siem_credential',
                    'account_password', 'account_password_staged'));

ALTER TABLE did.gateway_jobs DROP CONSTRAINT IF EXISTS gateway_jobs_kind_check;
ALTER TABLE did.gateway_jobs ADD CONSTRAINT gateway_jobs_kind_check
    CHECK (kind IN ('scan_accounts', 'rotate_credential', 'revoke_credential', 'decommission',
                    'grant_sudo', 'revoke_sudo', 'rotate_password'));
