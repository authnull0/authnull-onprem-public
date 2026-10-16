-- Authenticator: signing in to the organization from the app through the browser.
--
-- Idempotent: replayed against the master and every org database on every boot
-- (see docker-compose.yml).

-- Whether a phone added through the browser sign-in skips the second check (approval on
-- another phone or an email code). The user has just passed the org's own sign-in and MFA in
-- the browser. Off by default: the org's new_device_check applies as for any sign-in, and
-- new_device_check = 'admin' applies whatever this says.
ALTER TABLE did.mfa_device_settings
    ADD COLUMN IF NOT EXISTS browser_signin_skips_check boolean NOT NULL DEFAULT false;
