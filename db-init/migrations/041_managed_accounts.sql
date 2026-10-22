-- 041_managed_accounts.sql
--
-- Managed temporary accounts: a named local account an administrator creates
-- on an endpoint for a fixed time -- a contractor's or a vendor's -- with a
-- vaulted, rotated password, deleted when the time is up.
--
-- Creating one records a did.managed_accounts row and queues a
-- managed_account_add job. The gateway has the endpoint helper create the
-- account (marked as Authnull's by its GECOS field, with a throwaway random
-- password nobody sees) and schedule its own removal at the expiry. When the
-- gateway reports it created, the account joins the rotation profile chosen
-- for it (did.password_accounts, credential 'password') and its first
-- rotation is queued at once: from then on the password is the vault's, the
-- gateway logs in with it, and a reveal works as for any rotated account.
--
-- At the expiry -- or when an administrator removes it -- a
-- managed_account_del job deletes the account from the endpoint; its vaulted
-- password is retired and it leaves its profile.
--
-- Numbered 041, following 040_temp_users.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.managed_accounts (
    id                uuid        PRIMARY KEY,
    org_id            integer     NOT NULL,
    endpoint_id       bigint      NOT NULL,
    jump_server_id    integer     NOT NULL,
    account           text        NOT NULL,
    password_policy_id uuid       NOT NULL,
    note              text,
    status            text        NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'active', 'removing', 'removed', 'failed')),
    expires_at        timestamptz NOT NULL,
    created_by        integer,
    created_at        timestamptz NOT NULL DEFAULT now(),
    active_at         timestamptz,
    ended_at          timestamptz,
    end_reason        text,
    ended_by          integer,
    removed_at        timestamptz
);
CREATE INDEX IF NOT EXISTS managed_accounts_by_endpoint ON did.managed_accounts (org_id, endpoint_id, created_at DESC);
-- One live managed account of a name per endpoint.
CREATE UNIQUE INDEX IF NOT EXISTS managed_accounts_one_live
    ON did.managed_accounts (org_id, endpoint_id, account) WHERE status IN ('pending', 'active', 'removing');
CREATE INDEX IF NOT EXISTS managed_accounts_due ON did.managed_accounts (org_id, jump_server_id, expires_at)
    WHERE status IN ('pending', 'active');

-- gateway_jobs_kind_check is owned by 042_admin_account.sql; see the note there.