-- 043_local_users.sql
--
-- Local users: one place for an endpoint's accounts, without rotation
-- profiles.
--
-- * Per-account rotation. "Rotate this user's password every N days" is a
--   rotation profile of its own, kept out of the profile list: scope_endpoint_id
--   and scope_account name the one account it covers. Shared profiles leave
--   both NULL. An account's own profile takes precedence over any shared one
--   that names it.
--
-- * Add user. A managed account now logs in either with the key Authnull
--   already holds for it (credential 'key': no vaulted password, no rotation)
--   or with a vaulted, rotated password (credential 'password', in its own
--   per-account profile). And it may be permanent: expires_at NULL, removed
--   only when an administrator removes it (endpoint helper version 8).
--
-- * The endpoint's operating system and FQDN, read by each account scan
--   (os_name; fqdn already exists), and which local accounts have a password
--   set (password_state: {"alice": "P", "bob": "L", ...}, from passwd -S).
--
-- Numbered 043, following 042_admin_account.sql. Safe to run repeatedly.

ALTER TABLE did.password_policies ADD COLUMN IF NOT EXISTS scope_endpoint_id bigint;
ALTER TABLE did.password_policies ADD COLUMN IF NOT EXISTS scope_account text;
CREATE UNIQUE INDEX IF NOT EXISTS password_policies_one_per_account
    ON did.password_policies (org_id, scope_endpoint_id, scope_account) WHERE scope_endpoint_id IS NOT NULL;

ALTER TABLE did.managed_accounts ADD COLUMN IF NOT EXISTS credential text NOT NULL DEFAULT 'password';
ALTER TABLE did.managed_accounts DROP CONSTRAINT IF EXISTS managed_accounts_credential_check;
ALTER TABLE did.managed_accounts ADD CONSTRAINT managed_accounts_credential_check CHECK (credential IN ('key', 'password'));
ALTER TABLE did.managed_accounts ALTER COLUMN password_policy_id DROP NOT NULL;
ALTER TABLE did.managed_accounts ALTER COLUMN expires_at DROP NOT NULL;

ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS os_name text;
ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS password_state jsonb;
-- How often a password-credential managed account rotates once created; its
-- own profile is made when the endpoint reports the account exists.
ALTER TABLE did.managed_accounts ADD COLUMN IF NOT EXISTS rotation_interval_days integer;