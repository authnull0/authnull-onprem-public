-- TOTP for directory users: the second factor for when the phone is offline.
--
-- A directory user (did.ad_users, from the AD or Entra sync) signing in to an
-- application through the identity provider, or named by an application on
-- the MFA API, can answer with a 6-digit code from an authenticator app
-- instead of a push. Console users keep their own TOTP (did.mfa_methods).
--
-- authnull-service (internal/idp) enrols: it generates the secret, keeps it in
-- pending_secret_encrypted until the user confirms a first code, then moves it
-- to secret_encrypted. authn-service (/v4/directory/totp/verify) verifies.
-- Both encrypt with TOTP_ENCRYPTION_KEY, in console TOTP's format.
--
--   last_step           the 30-second step of the last code accepted: a code
--                       from that step or an earlier one is refused (replay)
--   backup_code_hashes  SHA-256 of each unused backup code, upper-case, no dash
--
-- Numbered 060, following 059_idp_mfa_api.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.directory_totp (
    id                       bigserial   PRIMARY KEY,
    org_id                   integer     NOT NULL,
    tenant_id                integer     NOT NULL,
    ad_user_id               integer     NOT NULL,
    secret_encrypted         text        NOT NULL DEFAULT '',
    pending_secret_encrypted text        NOT NULL DEFAULT '',
    backup_code_hashes       text[]      NOT NULL DEFAULT '{}',
    enabled                  boolean     NOT NULL DEFAULT true,
    verified_at              timestamptz,
    last_step                bigint,
    last_used_at             timestamptz,
    created_at               timestamptz NOT NULL DEFAULT now(),
    updated_at               timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS directory_totp_one_per_user
    ON did.directory_totp (org_id, tenant_id, ad_user_id);