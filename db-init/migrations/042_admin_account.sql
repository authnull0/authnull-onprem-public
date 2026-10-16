-- 042_admin_account.sql
--
-- Endpoints onboarded with an existing admin account instead of the setup
-- script (CyberArk calls this a reconcile account).
--
-- An administrator gives an account that already exists on the machine and
-- can use sudo -- its username and password, or private key. The credential is
-- kept in the vault (kind admin_credential, never shown again) and the
-- endpoint's access_mode becomes 'admin'. A bootstrap job then has the gateway
-- log in with it and install the Authnull helper and the grant-key sshd
-- setting through sudo -- the setup script without its authnull-svc account.
-- From then on every job on that endpoint logs in as the admin account and
-- runs the helper through sudo; endpoints set up with the script keep
-- access_mode 'svc' and work as before.
--
-- Numbered 042, following 041_managed_accounts.sql. Safe to run repeatedly.

ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS access_mode text NOT NULL DEFAULT 'svc';
ALTER TABLE did.epm_machines DROP CONSTRAINT IF EXISTS epm_machines_access_mode_check;
ALTER TABLE did.epm_machines ADD CONSTRAINT epm_machines_access_mode_check CHECK (access_mode IN ('svc', 'admin'));
-- The admin account's username, for display; the credential is in the vault.
ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS admin_account text;

-- This file owns the full kind lists of vault_secrets and gateway_jobs. Every migration is
-- replayed in order on each boot, so an earlier file that re-added its own shorter list would
-- reject rows of a later kind and, under set -e, stop every migration after it (024 to 041 used
-- to do exactly that). To add a kind, extend the list here, or move these statements to the new
-- file and delete them here: never leave two files setting the same constraint.
ALTER TABLE did.vault_secrets DROP CONSTRAINT IF EXISTS vault_secrets_kind_check;
ALTER TABLE did.vault_secrets ADD CONSTRAINT vault_secrets_kind_check
    CHECK (kind IN ('reconcile_key', 'grant_password', 'grant_key', 'storage_credential', 'siem_credential',
                    'account_password', 'account_password_staged', 'sso_client_secret', 'admin_credential',
                    -- 053: the organisation's SSH user CA private key.
                    'ssh_user_ca'));

ALTER TABLE did.gateway_jobs DROP CONSTRAINT IF EXISTS gateway_jobs_kind_check;
ALTER TABLE did.gateway_jobs ADD CONSTRAINT gateway_jobs_kind_check
    CHECK (kind IN ('scan_accounts', 'rotate_credential', 'revoke_credential', 'decommission',
                    'grant_sudo', 'revoke_sudo', 'rotate_password', 'temp_user_add', 'temp_user_del',
                    'managed_account_add', 'managed_account_del', 'bootstrap'));
