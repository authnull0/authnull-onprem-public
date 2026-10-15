-- Password SSH exceptions, in each ORGANISATION database.
--
-- Every managed endpoint accepts password SSH only from its gateway (036).
-- epm_machines.password_ssh_allow names accounts that may still use password
-- SSH directly -- a shared account people already log in to that way, say
-- -- on that one endpoint. Never root (no password SSH for root at all) and
-- never authnull-svc. The gateway passes the list to the helper on each scan.
--
-- Numbered 038, following 037_account_credential.sql. Safe to run repeatedly.

ALTER TABLE did.epm_machines ADD COLUMN IF NOT EXISTS password_ssh_allow jsonb NOT NULL DEFAULT '[]'::jsonb;
