-- 047: activation codes for Authenticator invites, and the per-org onboarding invite switch.
--
-- Per-org database. Replayed on every start (see docker-compose.yml): everything here is
-- IF NOT EXISTS.
--
-- Activation code: an 8-character code printed in the invite email, so a user without a working
-- camera can type it into the app instead of scanning the QR. It belongs to the invite row and
-- so lives and dies with it: it expires with the invite, and a re-sent invite (which marks the
-- old row used) kills the old code. Only a SHA-256 hash is stored. code_attempts counts wrong
-- codes entered against the invite; the invite stops accepting codes at 10.

ALTER TABLE did.mfa_device_enrollments
    ADD COLUMN IF NOT EXISTS activation_code_hash text,
    ADD COLUMN IF NOT EXISTS code_attempts integer NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX IF NOT EXISTS mfa_device_enrollments_activation_code_uq
    ON did.mfa_device_enrollments (org_id, activation_code_hash)
    WHERE activation_code_hash IS NOT NULL AND used = false;

-- Whether creating a user also mails them an Authenticator invite. No row means on.
CREATE TABLE IF NOT EXISTS did.mfa_onboarding_settings (
    org_id      integer     PRIMARY KEY,
    send_invite boolean     NOT NULL DEFAULT true,
    updated_by  integer,
    updated_at  timestamptz NOT NULL DEFAULT now()
);