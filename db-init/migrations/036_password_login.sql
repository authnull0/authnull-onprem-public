-- Logging in with a rotated password through the gateway, in each
-- ORGANISATION database.
--
-- A password policy's login_method says what its passwords are for:
--
--   'password' -- the gateway opens sessions to these accounts with the vaulted
--                 password, released once per approved session exactly as a
--                 grant key is (sshgrants.ReleaseForDecision). The operator
--                 never sees it, and Endpoint Policies install no key for
--                 these accounts: one credential per account.
--   'none'     -- rotation and break-glass reveal only; sessions use keys.
--
-- Every managed endpoint also gets an sshd rule from its helper (version 4):
-- password SSH only from its gateway's address, root never by password. Its
-- state, as last applied by a scan, is epm_machines.password_ssh.
--
-- Numbered 036, following 035_password_rotation.sql. Safe to run repeatedly.

ALTER TABLE did.password_policies ADD COLUMN IF NOT EXISTS login_method text NOT NULL DEFAULT 'password';
ALTER TABLE did.password_policies DROP CONSTRAINT IF EXISTS password_policies_login_method_check;
ALTER TABLE did.password_policies ADD CONSTRAINT password_policies_login_method_check
    CHECK (login_method IN ('password', 'none'));

-- 'gateway-only' (applied), or the reason it could not be.
ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS password_ssh text;

ALTER TABLE did.ssh_decisions ADD COLUMN IF NOT EXISTS released_credential text;