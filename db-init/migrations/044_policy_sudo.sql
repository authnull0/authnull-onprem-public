-- 044_policy_sudo.sql
--
-- Sudo from SSH policies. An SSH policy may carry ssh.sudo -- full sudo, or
-- named commands, for at most maxMinutes -- and every session it lets in,
-- approved with a second factor, is elevated with it, exactly as a sudo grant
-- elevates one (see 034_sudo_elevation.sql). The standalone grant stays for
-- what was set up with it.
--
-- An elevation now comes from a grant (grant_id) or a policy (policy_id, the
-- auth_policy_json row that allowed the session). Editing, suspending or
-- deleting the policy ends the elevations it gave.
--
-- Numbered 044, following 043_local_users.sql. Safe to run repeatedly.

ALTER TABLE did.sudo_elevations ALTER COLUMN grant_id DROP NOT NULL;
ALTER TABLE did.sudo_elevations ADD COLUMN IF NOT EXISTS policy_id uuid;
ALTER TABLE did.sudo_elevations DROP CONSTRAINT IF EXISTS sudo_elevations_source_check;
ALTER TABLE did.sudo_elevations ADD CONSTRAINT sudo_elevations_source_check
    CHECK (grant_id IS NOT NULL OR policy_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS sudo_elevations_by_policy ON did.sudo_elevations (org_id, policy_id)
    WHERE status IN ('pending', 'active');
