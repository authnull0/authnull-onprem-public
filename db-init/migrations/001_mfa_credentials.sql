-- did.credentials: WebAuthn/passkey credential records for the self-service console.
--
-- Written by ClientRepository.SaveCredential and read by GetCredentialsByClientID /
-- UpdateCredentialSignCount (internal/mfa/repo/repository.go). Mirrors the GORM model
-- internal/mfa/model/credential.go.
--
-- This table was missing entirely: it is absent from db-init/01_schema.sql and the repo has
-- no AutoMigrate, so passkey registration failed on insert.
--
-- NOTE ON EXTRA COLUMNS: the five columns marked "Credential Record flags" below are NOT in
-- the GORM model. They are required regardless -- see the block comment above them. Do not
-- "tidy" the table to match the model.
--
-- client_id holds strconv.Itoa(did.users.user_id) (see webauthn_handler.go), NOT a
-- did.clients.client_id -- did.clients deliberately does not exist. There is intentionally no
-- tenant_id/org_id column: isolation comes from the per-org database, within which
-- did.users.user_id is unique (tenants are distinguished by users.domain_id).

CREATE TABLE IF NOT EXISTS did.credentials (
    id                 uuid         DEFAULT gen_random_uuid() NOT NULL,
    client_id          text         NOT NULL,
    credential_id      bytea        NOT NULL,
    public_key         bytea        NOT NULL,
    attestation_type   text         NOT NULL DEFAULT '',

    -- Credential Record flags (webauthn.CredentialFlags) + attestation format.
    --
    -- backup_eligible is load-bearing, not metadata. The library compares the STORED value
    -- against the flag the authenticator presents on every assertion and rejects the login
    -- outright when they disagree ("Backup Eligible flag inconsistency detected during login
    -- validation" -- webauthn/login.go). Every synced passkey (iCloud Keychain, Google
    -- Password Manager, Windows Hello with sync) sets BE=1 at registration and at assertion,
    -- so without these columns registration succeeds and login fails 100% of the time with a
    -- misleading error. backup_state may legitimately change between logins; backup_eligible
    -- may not.
    attestation_format text         NOT NULL DEFAULT '',
    user_present       boolean      NOT NULL DEFAULT false,
    user_verified      boolean      NOT NULL DEFAULT false,
    backup_eligible    boolean      NOT NULL DEFAULT false,
    backup_state       boolean      NOT NULL DEFAULT false,

    aaguid             uuid,
    sign_count         bigint       NOT NULL DEFAULT 0,
    transports         text[],
    created_at         timestamptz  NOT NULL DEFAULT now(),
    updated_at         timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT credentials_pkey PRIMARY KEY (id)
);

-- Enforces the model's `unique` tag on CredentialID. Required for correctness, not hygiene:
-- UpdateCredentialSignCount updates WHERE credential_id = ? and would otherwise silently
-- touch several rows. Credential IDs are <= 1023 bytes, well inside the btree limit.
CREATE UNIQUE INDEX IF NOT EXISTS credentials_credential_id_key
    ON did.credentials USING btree (credential_id);

-- Every read filters on client_id.
CREATE INDEX IF NOT EXISTS credentials_client_id_idx
    ON did.credentials USING btree (client_id);

-- Align the seeded passkey factor name with what the code and the console both expect.
--
-- provisioning.go seeded this row as name='webauthn', but FinishRegistration looks it up by
-- name='Passkey', the console dispatches on `selectedMFA === "Passkey"`, and DeletePasskey
-- filters mfa_detail='Passkey' (which is populated from this description). Newly provisioned
-- orgs get the corrected values from the seed; this statement fixes any org database created
-- before that change. No-op where the row is already correct or absent -- note the master's
-- did.mfa_config is empty, since 01_schema.sql contains no INSERTs and these rows are seeded
-- per-org at provisioning time.
-- Guarded on the table existing: this file is replayed against every database, and a bare
-- UPDATE against a missing did.mfa_config aborts the whole run under ON_ERROR_STOP=1.
DO $$
BEGIN
    IF to_regclass('did.mfa_config') IS NOT NULL THEN
        UPDATE did.mfa_config
           SET name = 'Passkey',
               description = 'Passkey'
         WHERE name = 'webauthn';
    END IF;
END $$;
