-- Operator SSH certificates, in each ORGANISATION database.
--
-- WHAT THIS REPLACES
--
-- The SSH proxy used to learn who was connecting from a registered public key
-- (015_user_ssh_keys.sql): every operator's key had to be uploaded and kept in
-- step with their laptops. Instead, an operator who has signed in to the console
-- -- with the console's own SSO and MFA -- asks it to sign whatever key they
-- already have, and gets back a certificate that names them and expires on its
-- own. The proxy forwards the certificate; authn-service verifies it against the
-- CA below and reads the person from it.
--
-- TWO DIFFERENT CAs, ON PURPOSE
--
-- This is the USER CA: it vouches for PEOPLE, to the proxy. It is not the
-- gateway CA in /etc/authnull/sshproxy/ca_key, which vouches for the PROXY, to
-- targets. Targets trust only the gateway CA, so a certificate issued here opens
-- nothing if presented to a target directly.
--
-- ONE ACTIVE CA PER ORGANISATION
--
-- Created on first use by the console, never by hand. The partial unique index
-- makes a second active row unrepresentable, which is what lets two first-ever
-- requests race: both generate a key, one insert wins, both then read the winner.
-- retired_at exists so the CA can be rotated later without deleting the row that
-- signed every certificate in the ledger.
--
-- The private key is stored encrypted with the deployment's ENCRYPTION_KEY
-- (AES-256-GCM, see internal/pam/sshcerts). A database dump alone does not yield
-- a key that can mint an identity.
--
-- THE LEDGER
--
-- Every certificate issued, keyed by its serial. It is what makes revocation
-- possible -- authn-service refuses a certificate whose serial has revoked_at set
-- -- and it is the audit trail: who asked, for which key, from where, valid when.
-- Revocation is a timestamp, not a delete, for the same reason as in 015.
--
-- Numbered 020, following 019_jump_server_keys.sql. Safe to run repeatedly.

CREATE TABLE IF NOT EXISTS did.ssh_user_ca (
    id              serial PRIMARY KEY,
    org_id          integer     NOT NULL,
    public_key      text        NOT NULL,
    private_key_enc text        NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    retired_at      timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS ssh_user_ca_one_active
    ON did.ssh_user_ca (org_id) WHERE retired_at IS NULL;

CREATE TABLE IF NOT EXISTS did.ssh_user_certs (
    serial          bigint      PRIMARY KEY,
    org_id          integer     NOT NULL,
    ca_id           integer     NOT NULL REFERENCES did.ssh_user_ca (id),
    user_id         integer     NOT NULL,
    principal       text        NOT NULL,
    key_fingerprint text        NOT NULL,
    valid_after     timestamptz NOT NULL,
    valid_before    timestamptz NOT NULL,
    issued_at       timestamptz NOT NULL DEFAULT now(),
    source_ip       text,
    revoked_at      timestamptz
);

CREATE INDEX IF NOT EXISTS ssh_user_certs_by_user
    ON did.ssh_user_certs (org_id, user_id, issued_at DESC);