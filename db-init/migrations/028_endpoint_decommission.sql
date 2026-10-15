-- Decommissioning an endpoint, in each ORGANISATION database.
--
-- A new gateway job kind, "decommission": the gateway logs in as authnull-svc
-- one last time and has the helper remove everything the setup script installed
-- (grant keys, sshd drop-ins, sudoers line, the helper, then the account). The
-- control plane has already ended the endpoint's grants and retired their keys;
-- when the job reports back it retires the reconcile key and marks the endpoint
-- Decommissioned (did.epm_machines.status), which every path that issues keys,
-- scans or lists a gateway's endpoints then skips.
--
-- Numbered 028, following 027_endpoint_enrolment.sql. Safe to run repeatedly.

ALTER TABLE did.gateway_jobs DROP CONSTRAINT IF EXISTS gateway_jobs_kind_check;
ALTER TABLE did.gateway_jobs ADD CONSTRAINT gateway_jobs_kind_check
    CHECK (kind IN ('scan_accounts', 'rotate_credential', 'revoke_credential', 'decommission'));
