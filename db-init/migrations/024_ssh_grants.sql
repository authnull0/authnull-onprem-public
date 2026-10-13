-- SSH grants, in each ORGANISATION database: one policy's hold on one account
-- on one endpoint, and the credential issued for it.
--
-- A GRANT'S LIFE
--
--   pending  -> active    the gateway installed a fresh key for the account and
--                         the control plane stored it (vault + sealed grant key).
--   pending  -> failed    the install job ran out of attempts.
--   any      -> disabled  replaced by a newer grant for the same account, or its
--                         policy was edited or deleted. A disabled grant that was
--                         active gets a revoke job, which removes its key.
--
-- ONE ACTIVE GRANT PER ACCOUNT PER ENDPOINT
--
-- The partial unique index makes two live grants for one account on one machine
-- unrepresentable. A new grant for the same account replaces the old one -- the
-- previous holder loses it, and the new install overwrites the key.
--
-- THE GRANT KEY
--
-- The account's private key is stored in the vault (kind grant_key) already
-- encrypted under a per-grant key K. K itself is kept here, sealed under a key
-- derived from ENCRYPTION_KEY with a label distinct from the vault's. A stolen
-- vault table alone yields nothing; step 7 releases K for one session only after
-- MFA approval.
--
-- ALSO IN THIS MIGRATION
--
--   * revoke_credential joins the job kinds, so removing a key never collides
--     with the install job of the grant it removes.
--   * "one open job per endpoint and kind" becomes per endpoint, kind and
--     ACCOUNT (from the job payload), so granting two accounts on one machine
--     queues two jobs. Scan jobs carry no account and keep their old behaviour.
--
-- Numbered 024, following 023_gateway_jobs.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.ssh_grants (
    id               uuid        PRIMARY KEY,
    org_id           integer     NOT NULL,
    policy_id        uuid,
    endpoint_id      bigint      NOT NULL,
    account          text        NOT NULL,
    jump_server_id   integer     NOT NULL,
    status           text        NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'active', 'disabled', 'failed')),
    key_fingerprint  text,
    grant_key_sealed text,
    vault_secret_id  uuid,
    disabled_reason  text,
    created_by       integer,
    created_at       timestamptz NOT NULL DEFAULT now(),
    activated_at     timestamptz,
    disabled_at      timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS ssh_grants_one_live
    ON did.ssh_grants (org_id, endpoint_id, account) WHERE status IN ('pending', 'active');

CREATE INDEX IF NOT EXISTS ssh_grants_by_policy ON did.ssh_grants (org_id, policy_id);

ALTER TABLE did.gateway_jobs DROP CONSTRAINT IF EXISTS gateway_jobs_kind_check;
ALTER TABLE did.gateway_jobs ADD CONSTRAINT gateway_jobs_kind_check
    CHECK (kind IN ('scan_accounts', 'rotate_credential', 'revoke_credential'));

DROP INDEX IF EXISTS did.gateway_jobs_one_open;
CREATE UNIQUE INDEX IF NOT EXISTS gateway_jobs_one_open_per_account
    ON did.gateway_jobs (org_id, endpoint_id, kind, (coalesce(payload->>'account', '')))
    WHERE status IN ('queued', 'claimed');