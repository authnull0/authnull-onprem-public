-- The vault, in each ORGANISATION database: secrets the control plane holds for
-- SSH gateways, and a log of every time one was touched.
--
-- WHAT GOES IN IT
--
--   reconcile_key   the private key of an endpoint's authnull-svc account, which
--                   a gateway uses to scan accounts and rotate credentials there.
--                   One per endpoint, released to a gateway only for a job.
--   grant_password  a target account's rotated password, for one grant.
--   grant_key       a target account's rotated SSH private key, for one grant.
--
-- HOW IT IS ENCRYPTED (internal/pam/vault)
--
-- Envelope encryption. Every secret has its own random AES-256-GCM data key; the
-- data key is stored wrapped by a master key derived from the deployment's
-- ENCRYPTION_KEY. The org id, secret id, kind and version are authenticated data
-- on both layers, so a ciphertext copied to another row, another org, or an older
-- version does not decrypt. A database dump yields ciphertext only.
--
-- master_key_version records which master key wrapped the data key, so the master
-- can be rotated later by re-wrapping data keys without touching ciphertext.
--
-- ONE LIVE SECRET PER SLOT
--
-- (org, endpoint, kind, account) has at most one row that is not retired: the
-- partial unique index makes two live reconcile keys for one endpoint, or two
-- live passwords for one account, unrepresentable. Rotation updates the row in
-- place and increments version; retiring keeps the row for the audit trail.
--
-- THE ACCESS LOG
--
-- Every put, rotate, release, refused release and retire, with who asked (a
-- console user or a gateway), for which job, and why. The question after an
-- incident is always "who got this secret, and when" -- the log answers it
-- without the secret ever being in it.
--
-- These are SSH-gateway tables. The did.gateway_auth_events and
-- did.gateway_domain_mappings tables (007) belong to the AD gateway, unrelated.
--
-- Numbered 022, following 021_gateway_credentials.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.vault_secrets (
    id                 uuid        PRIMARY KEY,
    org_id             integer     NOT NULL,
    kind               text        NOT NULL
                       CHECK (kind IN ('reconcile_key', 'grant_password', 'grant_key')),
    endpoint_id        bigint      NOT NULL,
    account            text        NOT NULL,
    version            integer     NOT NULL DEFAULT 1,
    ciphertext         text        NOT NULL,
    wrapped_key        text        NOT NULL,
    master_key_version integer     NOT NULL DEFAULT 1,
    created_at         timestamptz NOT NULL DEFAULT now(),
    rotated_at         timestamptz,
    retired_at         timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS vault_secrets_one_live
    ON did.vault_secrets (org_id, endpoint_id, kind, account) WHERE retired_at IS NULL;

CREATE TABLE IF NOT EXISTS did.vault_access_log (
    id             bigserial   PRIMARY KEY,
    org_id         integer     NOT NULL,
    secret_id      uuid        NOT NULL,
    secret_version integer,
    action         text        NOT NULL
                   CHECK (action IN ('put', 'rotate', 'release', 'refuse', 'retire')),
    user_id        integer,
    jump_server_id integer,
    job_id         text,
    purpose        text,
    detail         text,
    at             timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vault_access_log_by_secret
    ON did.vault_access_log (org_id, secret_id, at DESC);