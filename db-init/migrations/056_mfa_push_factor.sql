-- Authenticator: Push as a second factor a tenant can offer at console sign-in.
--
-- Idempotent: replayed against the master and every org database on every boot
-- (see docker-compose.yml).

-- The factor catalogue (did.mfa_config) had no Push row, so a tenant could not choose it under
-- Tenant Configuration > Authentication factors and /mfa/status never listed it. Added beside
-- each catalogue's TOTP row, under that row's tenant, like the rest of the catalogue. A database
-- whose catalogue is still empty is skipped: new-tenant set-up seeds Push itself, and the
-- catalogue's ids are positional there. Offered, not turned on: an administrator picks it.
--
-- Name and description are both 'Push', as TOTP's and Passkey's are: the console matches on
-- the name, and the label comes from GetMFAStatus ("AuthNull Authenticator").
INSERT INTO did.mfa_config (tenant_id, name, description, status, factor_type, is_default)
SELECT DISTINCT c.tenant_id, 'Push', 'Push', 'Active', 'SECONDARY', false
FROM did.mfa_config c
WHERE c.name = 'TOTP'
  AND NOT EXISTS (
      SELECT 1 FROM did.mfa_config p
      WHERE p.name = 'Push' AND p.tenant_id IS NOT DISTINCT FROM c.tenant_id
  );