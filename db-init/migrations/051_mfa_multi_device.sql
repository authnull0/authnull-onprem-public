-- Authenticator: several phones per account, enrollment without a push token, device metadata.
--
-- Idempotent: replayed against the master and every org database on every boot
-- (see docker-compose.yml).

-- The full (org_id, push_transport, push_token) index is replaced by the partial
-- mfa_devices_org_transport_live_token_uq, created in 002 (see the note there for why
-- it lives in that file). Dropped here so a phone can enroll with push_token = ''.
DROP INDEX IF EXISTS did.mfa_devices_org_transport_token_uq;

-- (org_id, push_token) exists on some databases although no migration creates it (found on
-- alpha). It is stricter than the partial index, so while it exists the second tokenless phone
-- in an org fails with a unique violation.
DROP INDEX IF EXISTS did.mfa_devices_org_token_uq;

-- One identity, one phone, replaced by one link per (identity, device): the
-- mfa_device_identities_device_uq index created in 002.
DROP INDEX IF EXISTS did.mfa_device_identities_uq;

ALTER TABLE did.mfa_devices
    -- Reported by the app at enrollment; shown in the device list.
    ADD COLUMN IF NOT EXISTS device_model  text NOT NULL DEFAULT '',
    -- revoked_at set means signed out (by the phone, another phone, an admin or the new-device
    -- email). is_active only says whether a push can reach the phone: a dead token clears it.
    ADD COLUMN IF NOT EXISTS revoked_at    timestamptz,
    ADD COLUMN IF NOT EXISTS revoked_by    integer,
    ADD COLUMN IF NOT EXISTS revoke_reason text NOT NULL DEFAULT '';

-- Per-org Authenticator settings. An org without a row gets the defaults.
CREATE TABLE IF NOT EXISTS did.mfa_device_settings (
    org_id                   integer     PRIMARY KEY,
    max_devices_per_user     integer     NOT NULL DEFAULT 10
                             CHECK (max_devices_per_user BETWEEN 1 AND 10),
    -- Whether the app's own email + password sign-in may add a phone.
    allow_app_password_login boolean     NOT NULL DEFAULT true,
    -- The second check before a new phone is added.
    new_device_check         text        NOT NULL DEFAULT 'email_otp'
                             CHECK (new_device_check IN ('email_otp', 'sibling', 'admin')),
    updated_at               timestamptz NOT NULL DEFAULT now()
);
