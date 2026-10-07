-- Per-gateway client credentials, in each ORGANISATION database.
--
-- WHAT THIS REPLACES
--
-- Every gateway authenticated to the control plane with the same value: the
-- stack's INTERNAL_API_KEY, written into every console.env. One key for every
-- gateway, shared with authn-service, cannot be revoked for one gateway, and a
-- request carrying it can claim to be any gateway -- the heartbeat and the
-- recording upload took the jump server id from the request body.
--
-- Each gateway now gets its own client id and secret when an administrator
-- downloads its config. It exchanges them for a short-lived access token
-- (gateway_tokens) and presents that; the control plane derives the org and
-- the gateway from the token and refuses a body that names another. This is
-- also the precondition for releasing anything sensitive to a gateway -- the
-- vault will hand a reconcile key only to the gateway a job was given to.
--
-- SECRETS ARE STORED AS HASHES
--
-- secret_hash and token_hash are SHA-256 of 256-bit random values. A slow
-- password hash buys nothing for values that cannot be guessed, and costs a
-- hash per heartbeat. A database dump yields neither a usable secret nor a
-- usable token.
--
-- ONE ACTIVE CREDENTIAL PER GATEWAY
--
-- Downloading the config again issues a new credential and revokes the old one,
-- so a leaked console.env is fixed by downloading a fresh one. The partial unique
-- index makes two live credentials for one gateway unrepresentable. Revocation
-- is a timestamp, for the audit trail.
--
-- Numbered 021, following 020_ssh_user_certificates.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.gateway_credentials (
    id             serial      PRIMARY KEY,
    org_id         integer     NOT NULL,
    jump_server_id integer     NOT NULL,
    client_id      text        NOT NULL UNIQUE,
    secret_hash    text        NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    created_by     integer,
    last_used_at   timestamptz,
    revoked_at     timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS gateway_credentials_one_active
    ON did.gateway_credentials (org_id, jump_server_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS did.gateway_tokens (
    token_hash     text        PRIMARY KEY,
    credential_id  integer     NOT NULL REFERENCES did.gateway_credentials (id),
    org_id         integer     NOT NULL,
    jump_server_id integer     NOT NULL,
    issued_at      timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS gateway_tokens_expiry ON did.gateway_tokens (expires_at);