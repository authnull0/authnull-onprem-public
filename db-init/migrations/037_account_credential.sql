-- The Credential column: per account, per endpoint, which credential the
-- gateway opens sessions with, in each ORGANISATION database.
--
-- did.password_accounts.credential overrides the rotation profile's
-- login_method for one account on one endpoint:
--   'key'      -- a grant key, whatever the profile says;
--   'password' -- the rotated password (needs a current one);
--   NULL       -- the profile decides ('password' -> password, 'none' -> key).
--
-- Numbered 037, following 036_password_login.sql. Safe to run repeatedly.

ALTER TABLE did.password_accounts ADD COLUMN IF NOT EXISTS credential text;
ALTER TABLE did.password_accounts DROP CONSTRAINT IF EXISTS password_accounts_credential_check;
ALTER TABLE did.password_accounts ADD CONSTRAINT password_accounts_credential_check
    CHECK (credential IS NULL OR credential IN ('key', 'password'));
