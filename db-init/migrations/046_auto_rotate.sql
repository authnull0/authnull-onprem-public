-- 046_auto_rotate.sql
--
-- Take over discovered passwords. When an account scan finds an account with a
-- password set on an endpoint, its rotation is turned on (its own profile,
-- every 30 days, the first at once): the password nobody at Authnull knew is
-- replaced with one only the vault holds. Accounts with no password (key-only,
-- locked) are left alone; the gateway keeps opening them with session keys.
--
-- Never the endpoint's admin account (its vaulted credential would stop
-- working), root only with auto_rotate_root, never an Authnull-added account
-- (managed accounts choose for themselves), and never an account whose
-- rotation an administrator has set or turned off: an own profile in any state
-- means someone decided.
--
-- auto_rotate is on for every endpoint, existing ones included; per endpoint it
-- can be turned off. password_policies.auto marks a profile the scan created.
--
-- Numbered 046, following 045_ssh_name_login.sql. Safe to run repeatedly.

ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS auto_rotate boolean NOT NULL DEFAULT true;
ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS auto_rotate_root boolean NOT NULL DEFAULT false;
ALTER TABLE did.password_policies ADD COLUMN IF NOT EXISTS auto boolean NOT NULL DEFAULT false;